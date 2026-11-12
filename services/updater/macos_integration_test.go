package main

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
)

func TestMacImageValidationAndRollback(t *testing.T) {
	if runtime.GOOS != "darwin" || os.Getenv("ELEPHANT_UPDATER_INTEGRATION") != "1" {
		t.Skip("requires macOS image mounting")
	}
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	makeApp := func(path string, build int) {
		t.Helper()
		if err := os.MkdirAll(filepath.Join(path, "Contents", "MacOS"), 0700); err != nil {
			t.Fatal(err)
		}
		data := fmt.Sprintf(`<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string><key>CFBundleExecutable</key><string>ElephantRoute</string><key>CFBundleShortVersionString</key><string>2.1.0</string><key>CFBundleVersion</key><string>%d</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`, bundleID, build)
		if err := os.WriteFile(filepath.Join(path, "Contents", "Info.plist"), []byte(data), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := command("/bin/cp", executable, filepath.Join(path, "Contents", "MacOS", "ElephantRoute")); err != nil {
			t.Fatal(err)
		}
	}
	current := filepath.Join(root, "ElephantRoute.app")
	makeApp(current, 22101)
	imageRoot := filepath.Join(root, "image")
	makeApp(filepath.Join(imageRoot, "ElephantRoute.app"), 22102)
	id := "0123456789abcdef0123456789abcdef"
	taskDir := filepath.Join(root, id)
	if err := os.Mkdir(taskDir, 0700); err != nil {
		t.Fatal(err)
	}
	image := filepath.Join(taskDir, "installer.dmg")
	if _, err := command("/usr/bin/hdiutil", "create", "-quiet", "-srcfolder", imageRoot, "-format", "UDZO", image); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(image)
	if err != nil {
		t.Fatal(err)
	}
	hash := sha256.Sum256(data)
	exited := exec.Command("/usr/bin/true")
	if err := exited.Run(); err != nil {
		t.Fatal(err)
	}
	arch := runtime.GOARCH
	if arch == "amd64" {
		arch = "x64"
	}
	task := Task{ID: id, File: image, App: current, UID: os.Getuid(), PID: exited.Process.Pid, manifest: filepath.Join(taskDir, "install.json"), Release: Release{Version: "2.1.0", Build: 22102, Platform: "macos", Arch: arch, Size: int64(len(data)), SHA256: hex.EncodeToString(hash[:])}}
	if err := task.prepare(); err != nil {
		t.Fatal(err)
	}
	task.Release.Build = 22103
	if err := task.prepare(); err == nil {
		t.Fatal("wrong bundle build accepted")
	}
	task.Release.Build = 22102
	originalLaunch := launchMacApplication
	defer func() { launchMacApplication = originalLaunch }()
	launchMacApplication = func(task *Task) error {
		installed, err := info(task.App)
		if err != nil || installed["CFBundleVersion"] != "22102" {
			t.Fatal("new application was not staged atomically")
		}
		backup, err := info(filepath.Join(root, ".ElephantRoute-backup-"+id+".app"))
		if err != nil || backup["CFBundleVersion"] != "22101" {
			t.Fatal("old application backup missing")
		}
		return errors.New("simulated launch failure")
	}
	if err := task.installMac(); err == nil {
		t.Fatal("launch failure reported success")
	}
	restored, err := info(current)
	if err != nil || restored["CFBundleVersion"] != "22101" {
		t.Fatal("old application was not restored")
	}
}
