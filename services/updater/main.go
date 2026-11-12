package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"time"
)

type Release struct {
	Version  string `json:"version"`
	Build    int64  `json:"build_number"`
	Platform string `json:"platform"`
	Arch     string `json:"arch"`
	Size     int64  `json:"file_size"`
	SHA256   string `json:"sha256"`
}

type Task struct {
	ID       string  `json:"id"`
	File     string  `json:"file"`
	App      string  `json:"app"`
	PID      int     `json:"pid"`
	UID      int     `json:"uid"`
	Release  Release `json:"release"`
	manifest string
}

type Status struct {
	State string `json:"state"`
	Error string `json:"error,omitempty"`
}

var taskID = regexp.MustCompile(`^[a-f0-9]{32}$`)

func command(name string, args ...string) (string, error) {
	data, err := exec.Command(name, args...).CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s: %w: %s", filepath.Base(name), err, strings.TrimSpace(string(data)))
	}
	return strings.TrimSpace(string(data)), nil
}

func loadTask(path string) (*Task, error) {
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil || resolved != path || !filepath.IsAbs(path) {
		return nil, errors.New("invalid manifest path")
	}
	data, err := os.ReadFile(path)
	if err != nil || len(data) > 65536 {
		return nil, errors.New("invalid manifest")
	}
	var task Task
	if err := json.Unmarshal(data, &task); err != nil {
		return nil, err
	}
	if !taskID.MatchString(task.ID) || filepath.Base(filepath.Dir(path)) != task.ID || filepath.Base(path) != "install.json" || task.PID <= 1 || task.UID <= 0 {
		return nil, errors.New("invalid update task")
	}
	if os.Geteuid() != 0 && task.UID != os.Getuid() {
		return nil, errors.New("update owner mismatch")
	}
	if task.Release.Platform != runtime.GOOS && !(task.Release.Platform == "macos" && runtime.GOOS == "darwin") {
		return nil, errors.New("wrong update platform")
	}
	arch := map[string]string{"amd64": "x64", "386": "x86"}[runtime.GOARCH]
	if arch == "" {
		arch = runtime.GOARCH
	}
	if task.Release.Arch != arch {
		return nil, errors.New("wrong update architecture")
	}
	extension := "deb"
	if runtime.GOOS == "darwin" {
		extension = "dmg"
	}
	if task.File != filepath.Join(filepath.Dir(path), "installer."+extension) {
		return nil, errors.New("invalid artifact path")
	}
	app, err := filepath.EvalSymlinks(task.App)
	if err != nil || app != task.App || !filepath.IsAbs(app) {
		return nil, errors.New("invalid application path")
	}
	task.manifest = path
	if err := task.verify(); err != nil {
		return nil, err
	}
	return &task, nil
}

func (t *Task) verify() error {
	info, err := os.Lstat(t.File)
	if err != nil || !info.Mode().IsRegular() || info.Size() != t.Release.Size || t.Release.Size <= 0 || !regexp.MustCompile(`^[a-f0-9]{64}$`).MatchString(t.Release.SHA256) {
		return errors.New("invalid artifact size or type")
	}
	file, err := os.Open(t.File)
	if err != nil {
		return err
	}
	defer file.Close()
	hash := sha256.New()
	if _, err := io.Copy(hash, file); err != nil {
		return err
	}
	if hex.EncodeToString(hash.Sum(nil)) != t.Release.SHA256 {
		return errors.New("artifact checksum mismatch")
	}
	return nil
}

func (t *Task) status(state string, err error) error {
	value := Status{State: state}
	if err != nil {
		value.Error = err.Error()
	}
	data, _ := json.Marshal(value)
	path := filepath.Join(filepath.Dir(t.manifest), "install-state.json")
	temporary, err := os.CreateTemp(filepath.Dir(path), ".update-state-")
	if err != nil {
		return err
	}
	defer os.Remove(temporary.Name())
	if err := temporary.Chmod(0644); err != nil {
		temporary.Close()
		return err
	}
	if _, err := temporary.Write(data); err != nil {
		temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporary.Name(), path)
}

func (t *Task) waitForExit() error {
	if err := t.status("waitingForExit", nil); err != nil {
		return err
	}
	core := filepath.Join(filepath.Dir(t.App), "FlClashCore")
	if runtime.GOOS == "darwin" {
		core = filepath.Join(t.App, "Contents", "MacOS", "FlClashCore")
	}
	deadline := time.Now().Add(45 * time.Second)
	for time.Now().Before(deadline) {
		_, parentErr := exec.Command("/bin/ps", "-p", strconv.Itoa(t.PID), "-o", "pid=").Output()
		processes, queryErr := command("/bin/ps", "-ax", "-o", "command=")
		if parentErr != nil && queryErr == nil && !containsProcess(processes, core) {
			return nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	return errors.New("application did not exit; installation cancelled")
}

func containsProcess(processes, executable string) bool {
	for _, line := range strings.Split(processes, "\n") {
		line = strings.TrimSpace(line)
		if line == executable || strings.HasPrefix(line, executable+" ") {
			return true
		}
	}
	return false
}

func (t *Task) prepare() error {
	if runtime.GOOS == "darwin" {
		return t.prepareMac()
	}
	if runtime.GOOS == "linux" {
		return t.prepareLinux()
	}
	return errors.New("unsupported installer")
}

func (t *Task) install() error {
	if err := t.prepare(); err != nil {
		return err
	}
	if runtime.GOOS == "darwin" {
		return t.installMac()
	}
	return t.installLinux()
}

func main() {
	if len(os.Args) != 3 {
		os.Exit(2)
	}
	task, err := loadTask(os.Args[2])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	switch os.Args[1] {
	case "--prepare":
		err = task.prepare()
	case "--install":
		err = task.install()
	default:
		err = errors.New("unsupported updater operation")
	}
	if err != nil {
		task.status("failed", err)
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
