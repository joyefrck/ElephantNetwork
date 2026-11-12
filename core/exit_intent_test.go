package core

import "testing"

func TestTerminationRejectsNewInitializationAndConfiguration(t *testing.T) {
	wasInit := isInit.Load()
	isExiting.Store(true)
	t.Cleanup(func() { isExiting.Store(false); isInit.Store(wasInit) })
	if handleInitClash(&InitParams{}) {
		t.Fatal("terminal Core accepted initialization")
	}
	if handleStartListener() {
		t.Fatal("terminal Core reopened listeners")
	}
	if err := applyConfig(&SetupParams{}); err == nil {
		t.Fatal("terminal Core accepted configuration")
	}
	if value := handleUpdateConfig(&UpdateParams{}); value == "" {
		t.Fatal("terminal Core accepted an update")
	}
	if value := handleUpdateRuntimeConfig(map[string]any{}); value == "" {
		t.Fatal("terminal Core accepted runtime configuration")
	}
}
