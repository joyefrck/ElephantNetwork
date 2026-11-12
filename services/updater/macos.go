package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const bundleID = "com.elphantroute.elephantNetwork"

func info(app string) (map[string]any, error) {
	data, err := command("/usr/bin/plutil", "-convert", "json", "-o", "-", filepath.Join(app, "Contents", "Info.plist"))
	if err != nil {
		return nil, err
	}
	var value map[string]any
	if err := json.Unmarshal([]byte(data), &value); err != nil {
		return nil, err
	}
	if value["CFBundleIdentifier"] != bundleID {
		return nil, errors.New("application bundle identifier mismatch")
	}
	executable, ok := value["CFBundleExecutable"].(string)
	if !ok || executable == "" || filepath.Base(executable) != executable {
		return nil, errors.New("invalid bundle executable")
	}
	return value, nil
}

func (t *Task) mountMac() (string, func(), error) {
	mount := filepath.Join(filepath.Dir(t.manifest), "mount")
	if err := os.MkdirAll(mount, 0700); err != nil {
		return "", nil, err
	}
	if _, err := command("/usr/bin/hdiutil", "attach", "-readonly", "-nobrowse", "-noautoopen", "-mountpoint", mount, t.File); err != nil {
		return "", nil, err
	}
	return filepath.Join(mount, "ElephantRoute.app"), func() { command("/usr/bin/hdiutil", "detach", mount) }, nil
}

func teamID(app string) string {
	output, _ := exec.Command("/usr/bin/codesign", "-dv", "--verbose=4", app).CombinedOutput()
	for _, line := range strings.Split(string(output), "\n") {
		if strings.HasPrefix(line, "TeamIdentifier=") {
			value := strings.TrimPrefix(line, "TeamIdentifier=")
			if value != "not set" {
				return value
			}
		}
	}
	return ""
}

func (t *Task) validateMac(app string) error {
	original, err := info(t.App)
	if err != nil {
		return err
	}
	next, err := info(app)
	if err != nil {
		return err
	}
	if next["CFBundleShortVersionString"] != t.Release.Version || fmt.Sprint(next["CFBundleVersion"]) != strconv.FormatInt(t.Release.Build, 10) {
		return errors.New("bundle version mismatch")
	}
	arch := "arm64"
	if t.Release.Arch == "x64" {
		arch = "x86_64"
	}
	if _, err := command("/usr/bin/lipo", filepath.Join(app, "Contents", "MacOS", next["CFBundleExecutable"].(string)), "-verify_arch", arch); err != nil {
		return err
	}
	if publisher := teamID(t.App); publisher != "" {
		if teamID(app) != publisher {
			return errors.New("bundle publisher mismatch")
		}
		if _, err := command("/usr/bin/codesign", "--verify", "--deep", "--strict", app); err != nil {
			return err
		}
	}
	if original["CFBundleIdentifier"] != next["CFBundleIdentifier"] {
		return errors.New("bundle identity mismatch")
	}
	return nil
}

func (t *Task) prepareMac() error {
	if filepath.Ext(t.App) != ".app" {
		return errors.New("updates require an installed application bundle")
	}
	app, detach, err := t.mountMac()
	if err != nil {
		return err
	}
	defer detach()
	return t.validateMac(app)
}

func shellQuote(value string) string { return "'" + strings.ReplaceAll(value, "'", "'\\''") + "'" }

var launchMacApplication = func(t *Task) error {
	var launchErr error
	if os.Geteuid() == 0 {
		_, launchErr = command("/bin/launchctl", "asuser", strconv.Itoa(t.UID), "/usr/bin/sudo", "-u", "#"+strconv.Itoa(t.UID), "/usr/bin/open", t.App)
	} else {
		_, launchErr = command("/usr/bin/open", t.App)
	}
	return launchErr
}

func (t *Task) installMac() error {
	parent := filepath.Dir(t.App)
	stage := filepath.Join(parent, ".ElephantRoute-update-"+t.ID+".app")
	backup := filepath.Join(parent, ".ElephantRoute-backup-"+t.ID+".app")
	if os.Geteuid() == 0 && t.App != "/Applications/ElephantRoute.app" {
		return errors.New("elevated updater only supports the standard application location")
	}
	if err := os.Mkdir(stage, 0700); err != nil {
		if !os.IsPermission(err) || os.Geteuid() == 0 {
			return err
		}
		updater, err := os.Executable()
		if err != nil {
			return err
		}
		script := "do shell script " + strconv.Quote(shellQuote(updater)+" --install "+shellQuote(t.manifest)) + " with administrator privileges"
		if _, err := command("/usr/bin/osascript", "-e", script); err != nil {
			return err
		}
		return nil
	}
	defer os.RemoveAll(stage)
	if _, err := os.Lstat(backup); !os.IsNotExist(err) {
		return errors.New("update backup already exists")
	}
	app, detach, err := t.mountMac()
	if err != nil {
		return err
	}
	if err := t.validateMac(app); err != nil {
		detach()
		return err
	}
	_, err = command("/usr/bin/ditto", app, stage)
	detach()
	if err != nil {
		return err
	}
	if err := t.validateMac(stage); err != nil {
		return err
	}
	if err := t.waitForExit(); err != nil {
		return err
	}
	if err := os.Rename(t.App, backup); err != nil {
		return err
	}
	if err := os.Rename(stage, t.App); err != nil {
		os.Rename(backup, t.App)
		return err
	}
	launchErr := launchMacApplication(t)
	if launchErr != nil {
		failed := filepath.Join(parent, ".ElephantRoute-failed-"+t.ID+".app")
		if err := os.Rename(t.App, failed); err == nil {
			os.Rename(backup, t.App)
		}
		return launchErr
	}
	time.Sleep(time.Second)
	return t.status("installed", nil)
}
