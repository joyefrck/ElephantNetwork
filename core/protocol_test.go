//go:build !cgo

package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
)

type protocolConnection struct{ bytes.Buffer }

func (c *protocolConnection) Close() error { return nil }

func protocolResponse(t *testing.T, method CoreMethod, arguments string) MethodResponse {
	t.Helper()
	previous := conn
	connection := &protocolConnection{}
	conn = connection
	defer func() { conn = previous }()
	handleMethodCall(&MethodCall{ID: "request", Method: method, Arguments: json.RawMessage(arguments)}, MethodResponse{ID: "request"})
	data, err := readFrame(connection)
	if err != nil {
		t.Fatal(err)
	}
	var response MethodResponse
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	if response.ID != "request" {
		t.Fatal("response lost request identity")
	}
	if _, err := connection.ReadByte(); err != io.EOF {
		t.Fatal("method sent multiple responses")
	}
	return response
}

func TestProtocolTypedErrorsAndObjectArguments(t *testing.T) {
	for _, args := range []string{"", "null", "true", "42", `"path"`, "[]", "  "} {
		response := protocolResponse(t, configUpdateMethod, args)
		if response.Error == nil || response.Error.Code != "invalid_arguments" || response.Result != nil {
			t.Fatalf("invalid argument accepted: %q %#v", args, response)
		}
	}
	response := protocolResponse(t, CoreMethod("updateConfig"), "{}")
	if response.Error == nil || response.Error.Code != "not_implemented" {
		t.Fatal("legacy protocol accepted")
	}
	old := currentConfig
	currentConfig = nil
	defer func() { currentConfig = old }()
	response = protocolResponse(t, configUpdateMethod, "{}")
	if response.Error == nil || response.Error.Code != "core_error" {
		t.Fatal("configuration failure was returned as success")
	}
	response = protocolResponse(t, configReadMethod, `{"path":"/missing/elephant-config.yaml"}`)
	if response.Error == nil || response.Error.Code != "core_error" {
		t.Fatal("read failure was returned as success")
	}
}

func TestRejectedSetupRetainsActiveConfigurationAndOptions(t *testing.T) {
	home := constant.Path.HomeDir()
	url := constant.DefaultTestURL
	old := currentConfig
	currentConfig = &config.Config{}
	active := currentConfig
	defer func() { currentConfig = old; constant.SetHomeDir(home); constant.DefaultTestURL = url }()
	root := t.TempDir()
	constant.SetHomeDir(root)
	if err := os.WriteFile(filepath.Join(root, "config.yaml"), []byte("proxies: [invalid\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := applyConfig(&SetupParams{TestURL: "https://changed.test"}); err == nil {
		t.Fatal("invalid setup succeeded")
	}
	if currentConfig != active || constant.DefaultTestURL != url {
		t.Fatal("failed setup replaced active state")
	}
}

func TestResponseEncodingFailureIsAnErrorEnvelope(t *testing.T) {
	data, err := (MethodResponse{ID: "invalid", Result: func() {}}).JSON()
	if err != nil {
		t.Fatal(err)
	}
	var response MethodResponse
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	if response.ID != "invalid" || response.Error == nil || response.Error.Code != "internal_error" || response.Result != nil {
		t.Fatal("unencodable result lost its error response")
	}
	data, err = (MethodResponse{ID: "command"}).JSON()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Contains(data, []byte(`"result":null`)) {
		t.Fatal("command success must be null")
	}
}
