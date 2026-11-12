package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

func fixture(t *testing.T) (string, Task) {
	t.Helper()
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	id := "0123456789abcdef0123456789abcdef"
	directory := filepath.Join(root, id)
	if err := os.Mkdir(directory, 0700); err != nil {
		t.Fatal(err)
	}
	extension := "deb"
	platform := runtime.GOOS
	if platform == "darwin" {
		platform = "macos"
		extension = "dmg"
	}
	arch := runtime.GOARCH
	if arch == "amd64" {
		arch = "x64"
	}
	data := []byte("private installer fixture")
	hash := sha256.Sum256(data)
	app := filepath.Join(root, "ElephantRoute.app")
	if err := os.Mkdir(app, 0700); err != nil {
		t.Fatal(err)
	}
	task := Task{ID: id, File: filepath.Join(directory, "installer."+extension), App: app, PID: os.Getpid(), UID: os.Getuid(), Release: Release{Version: "2.1.0", Build: 22102, Platform: platform, Arch: arch, Size: int64(len(data)), SHA256: hex.EncodeToString(hash[:])}}
	if err := os.WriteFile(task.File, data, 0600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(directory, "install.json")
	writeTask(t, path, task)
	return path, task
}

func writeTask(t *testing.T, path string, task Task) {
	t.Helper()
	data, err := json.Marshal(task)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, data, 0600); err != nil {
		t.Fatal(err)
	}
}

func TestLoadTask(t *testing.T) {
	path, task := fixture(t)
	if _, err := loadTask(path); err != nil {
		t.Fatal(err)
	}
	for name, change := range map[string]func(*Task){
		"escape":             func(t *Task) { t.ID = "../../escaped" },
		"wrong platform":     func(t *Task) { t.Release.Platform = "android" },
		"wrong architecture": func(t *Task) { t.Release.Arch = "invalid" },
		"wrong size":         func(t *Task) { t.Release.Size++ },
		"wrong hash":         func(t *Task) { t.Release.SHA256 = string(make([]byte, 64)) },
		"wrong file":         func(t *Task) { t.File = filepath.Join(filepath.Dir(t.File), "unrelated") },
		"wrong user":         func(t *Task) { t.UID++ },
		"invalid pid":        func(t *Task) { t.PID = 1 },
	} {
		t.Run(name, func(t *testing.T) {
			altered := task
			change(&altered)
			writeTask(t, path, altered)
			if _, err := loadTask(path); err == nil {
				t.Fatal("unsafe update task accepted")
			}
		})
	}
}

func TestRejectArtifactSymlink(t *testing.T) {
	path, task := fixture(t)
	target := filepath.Join(filepath.Dir(task.File), "outside")
	if err := os.Rename(task.File, target); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, task.File); err != nil {
		t.Fatal(err)
	}
	if _, err := loadTask(path); err == nil {
		t.Fatal("artifact symlink accepted")
	}
}

func TestStatusDoesNotFollowSymlinks(t *testing.T) {
	path, _ := fixture(t)
	task, err := loadTask(path)
	if err != nil {
		t.Fatal(err)
	}
	unrelated := filepath.Join(filepath.Dir(path), "unrelated")
	if err := os.WriteFile(unrelated, []byte("retained"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(unrelated, filepath.Join(filepath.Dir(path), "install-state.json")); err != nil {
		t.Fatal(err)
	}
	if err := task.status("waitingForExit", nil); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(unrelated)
	if err != nil || string(data) != "retained" {
		t.Fatal("status modified an unrelated file")
	}
	var status Status
	data, err = os.ReadFile(filepath.Join(filepath.Dir(path), "install-state.json"))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &status); err != nil || status.State != "waitingForExit" {
		t.Fatal("status not persisted")
	}
}

func TestCoreExitCheckMatchesOnlyOwnedExecutable(t *testing.T) {
	core := "/Applications/Elephant Route.app/Contents/MacOS/FlClashCore"
	if !containsProcess(core+" --address /tmp/pipe", core) {
		t.Fatal("running owned core was ignored")
	}
	if containsProcess(core+"Other --address /tmp/pipe", core) {
		t.Fatal("unrelated executable matched")
	}
	if containsProcess("/another/app/FlClashCore", core) {
		t.Fatal("another app's core matched")
	}
}
