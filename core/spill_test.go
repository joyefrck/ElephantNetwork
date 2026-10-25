package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/constant"
)

func TestSpillNeverWritesOrCleansThroughADirectorySymlink(t *testing.T) {
	home := t.TempDir()
	outside := t.TempDir()
	previousHome := constant.Path.HomeDir()
	constant.SetHomeDir(home)
	defer constant.SetHomeDir(previousHome)
	if err := os.Symlink(outside, filepath.Join(home, "responses")); err != nil {
		t.Skipf("directory symlinks unavailable: %v", err)
	}
	protected := filepath.Join(outside, "response-protected.json")
	if err := os.WriteFile(protected, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := writeSpilledResponse([]byte("{}")); err == nil {
		t.Fatal("spill followed a directory symlink")
	}
	cleanupSpilledResponses()
	if content, err := os.ReadFile(protected); err != nil || string(content) != "keep" {
		t.Fatalf("cleanup changed an external file: %q %v", content, err)
	}
}
