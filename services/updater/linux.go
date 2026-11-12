package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
)

func (t *Task) prepareLinux() error {
	if os.Geteuid() == 0 {
		return errors.New("start the updater as the desktop user")
	}
	owner, err := command("/usr/bin/dpkg-query", "-S", t.App)
	if err != nil || !strings.HasPrefix(owner, "elephant-network: ") {
		return errors.New("application is not managed by the official DEB package")
	}
	value, err := command("/usr/bin/dpkg-deb", "-f", t.File, "Package", "Architecture", "Version")
	if err != nil {
		return err
	}
	fields := map[string]string{}
	for _, line := range strings.Split(value, "\n") {
		pair := strings.SplitN(line, ": ", 2)
		if len(pair) == 2 {
			fields[pair[0]] = pair[1]
		}
	}
	arch := map[string]string{"x64": "amd64", "arm64": "arm64", "x86": "i386", "arm": "armhf"}[t.Release.Arch]
	if fields["Package"] != "elephant-network" || fields["Architecture"] != arch || fields["Version"] != t.Release.Version+"+"+strconv.FormatInt(t.Release.Build, 10) {
		return errors.New("DEB package identity, architecture or version mismatch")
	}
	if _, err := os.Stat("/usr/bin/pkexec"); err != nil {
		return err
	}
	return nil
}

func (t *Task) installLinux() error {
	if err := t.waitForExit(); err != nil {
		return err
	}
	_, err := command("/usr/bin/pkexec", "/usr/bin/apt-get", "install", "--yes", "--", t.File)
	if err != nil {
		t.status("failed", err)
		exec.Command(t.App).Start()
		return err
	}
	app := exec.Command(t.App)
	app.Dir = filepath.Dir(t.App)
	if err := app.Start(); err != nil {
		return err
	}
	app.Process.Release()
	return t.status("installed", nil)
}
