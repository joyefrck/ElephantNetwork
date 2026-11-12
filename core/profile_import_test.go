package core

import (
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	rp "github.com/metacubex/mihomo/rules/provider"
)

func TestReadProfilePreservesUnknownConfigurationFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\nfuture-feature:\n  enabled: true\n  values: [one, two]\n"), 0600); err != nil {
		t.Fatal(err)
	}
	raw, err := handleGetConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	feature, ok := raw["future-feature"].(map[string]any)
	if !ok || feature["enabled"] != true || !reflect.DeepEqual(feature["values"], []any{"one", "two"}) {
		t.Fatal("unknown fields were dropped")
	}
	if _, exists := raw["rules"]; !exists {
		t.Fatal("rules key was lost")
	}
}

func TestProfileValidationRejectsUnknownProtocolsBeforeAnImport(t *testing.T) {
	path := filepath.Join(t.TempDir(), "profile.yaml")
	if err := os.WriteFile(path, []byte("proxies:\n  - {name: invalid, type: unknown-protocol}\nrules: [MATCH,DIRECT]\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if result := validateProfileConfig(path, true); result == "" {
		t.Fatal("unsupported proxy passed validation")
	}
	if err := os.WriteFile(path, []byte("proxies: []\nproxy-groups: []\nrules:\n  - MATCH,DIRECT\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if result := validateProfileConfig(path, true); result != "" {
		t.Fatal(result)
	}
}

func TestProviderImportFailuresPropagateAndRetainExistingFiles(t *testing.T) {
	root := t.TempDir()
	proxyPath := filepath.Join(root, "proxy.yaml")
	rulePath := filepath.Join(root, "rule.yaml")
	for _, path := range []string{proxyPath, rulePath} {
		if err := os.WriteFile(path, []byte("original"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	parseError := errors.New("invalid provider contents")
	proxy, err := provider.NewProxySetProvider("proxy", 0, nil,
		func([]byte) ([]constant.Proxy, error) { return nil, parseError },
		resource.NewFileVehicle(proxyPath), provider.NewHealthCheck(nil, "", 100, 0, true, nil))
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	if err := sideUpdateExternalProvider(proxy, []byte("invalid")); !errors.Is(err, parseError) {
		t.Fatalf("proxy import hid its error: %v", err)
	}
	rule := rp.NewRuleSetProvider("rule", P.Domain, P.YamlRule, 0, resource.NewFileVehicle(rulePath), nil, nil, nil)
	defer rule.(*rp.RuleSetProvider).Close()
	if err := sideUpdateExternalProvider(rule, []byte("invalid")); err == nil {
		t.Fatal("rule import hid its error")
	}
	for _, path := range []string{proxyPath, rulePath} {
		bytes, err := os.ReadFile(path)
		if err != nil || string(bytes) != "original" {
			t.Fatalf("failed import changed %s", path)
		}
	}
}
