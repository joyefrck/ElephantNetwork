package main

import (
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/config"
)

func TestRuntimeUpdatePreservesProxyOrderAndRejectsInvalidSections(t *testing.T) {
	previous := currentConfig
	previousNames := config.GetProxyNameList()
	defer func() {
		currentConfig = previous
		config.SetProxyNameList(previousNames)
	}()
	var err error
	currentConfig, err = config.ParseRawConfig(config.DefaultRawConfig())
	if err != nil {
		t.Fatal(err)
	}
	names := []string{"Existing group", "GLOBAL"}
	config.SetProxyNameList(names)

	if message := handleUpdateRuntimeConfig(map[string]any{
		"hosts": map[string]any{"example.test": "127.0.0.2"},
	}); message != "" {
		t.Fatal(message)
	}
	if !reflect.DeepEqual(config.GetProxyNameList(), names) {
		t.Fatalf("proxy order changed: %v", config.GetProxyNameList())
	}
	accepted := currentConfig.DNS
	if message := handleUpdateRuntimeConfig(map[string]any{
		"dns": map[string]any{"enable": true, "nameserver": []string{"unsupported://resolver"}},
	}); message == "" {
		t.Fatal("invalid DNS was accepted")
	}
	if currentConfig.DNS != accepted {
		t.Fatal("invalid DNS changed the active config")
	}
	if !reflect.DeepEqual(config.GetProxyNameList(), names) {
		t.Fatal("failed DNS parsing changed proxy order")
	}
	if message := handleUpdateRuntimeConfig(map[string]any{"proxies": []any{}}); message == "" {
		t.Fatal("runtime patch accepted a structural section")
	}
}
