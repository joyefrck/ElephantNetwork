package mobile

import (
	"errors"
	"testing"
)

type failingCallbacks struct{ fail bool }

func (c failingCallbacks) Protect(fd int32) (bool, error) {
	if c.fail {
		return true, errors.New("Java protection callback failed")
	}
	return fd > 0, nil
}
func (c failingCallbacks) ResolveProcess(protocol int32, source, target string, uid int32) (string, error) {
	if c.fail {
		return "untrusted", errors.New("Java process resolver failed")
	}
	return "com.example.app", nil
}

func TestCallbackErrorsCannotBecomeSuccessfulNativeResults(t *testing.T) {
	failed := tunCallbacks{handler: failingCallbacks{fail: true}}
	if failed.Protect(1) {
		t.Fatal("Java exception became successful socket protection")
	}
	if failed.ResolveProcess(6, "127.0.0.1:1", "127.0.0.1:2", 1000) != "" {
		t.Fatal("Java exception returned a package")
	}
	working := tunCallbacks{handler: failingCallbacks{}}
	if !working.Protect(1) || working.Protect(-1) {
		t.Fatal("protection result changed")
	}
	if working.ResolveProcess(6, "127.0.0.1:1", "127.0.0.1:2", 1000) != "com.example.app" {
		t.Fatal("process resolver result changed")
	}
}
