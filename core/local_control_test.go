package main

import (
	"net/netip"
	"strings"
	"testing"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/config"
	authStore "github.com/metacubex/mihomo/listener/auth"
)

func TestLocalControllerRequiresSecretAndRemovesAlternativeEntrypoints(t *testing.T) {
	for _, secret := range []string{"", "short", strings.Repeat("a", 32) + "\n", strings.Repeat("a", 64)} {
		cfg := &config.Config{Controller: &config.Controller{
			ExternalController: "127.0.0.1:9090", ExternalControllerTLS: "0.0.0.0:9091",
			ExternalControllerUnix: "/tmp/foreign.sock", ExternalControllerPipe: "foreign", Secret: secret,
		}}
		rc := localControllerConfig(cfg, &UpdateParams{})
		if (rc.Addr != "") != (secret == strings.Repeat("a", 64)) {
			t.Fatal("controller did not enforce credentials")
		}
		if rc.TLSAddr != "" || rc.UnixAddr != "" || rc.PipeAddr != "" || cfg.Controller.ExternalControllerUnix != "" {
			t.Fatal("alternative endpoint survived")
		}
		if rc.Secret != secret {
			t.Fatal("secret was lost")
		}
	}
}

func TestRuntimeAuthenticationRejectsInvalidUsersAndLoopbackExemptions(t *testing.T) {
	old := authStore.Default.Authenticator()
	oldPrefixes := inbound.SkipAuthPrefixes()
	defer authStore.Default.SetAuthenticator(old)
	defer inbound.SetSkipAuthPrefixes(oldPrefixes)
	cfg := &config.Config{General: &config.General{}}
	inbound.SetSkipAuthPrefixes([]netip.Prefix{netip.MustParsePrefix("127.0.0.0/8")})
	if err := applyAuthentication(cfg, []string{"user:pass:word"}); err != nil {
		t.Fatal(err)
	}
	current := authStore.Default.Authenticator()
	if current == nil || !current.Verify("user", "pass:word") || current.Verify("user", "wrong") || current.Verify("", "") {
		t.Fatal("runtime credentials were not enforced")
	}
	if inbound.SkipAuthRemoteAddress("127.0.0.1:1234") || inbound.SkipAuthRemoteAddress("[::1]:1234") {
		t.Fatal("loopback bypassed authentication")
	}
	for _, value := range []string{"", "user:", ":pass", "user name:pass", "user:pass\n"} {
		if err := applyAuthentication(cfg, []string{value}); err == nil {
			t.Fatal("invalid credentials accepted")
		}
		if !authStore.Default.Authenticator().Verify("user", "pass:word") {
			t.Fatal("invalid update discarded prior credentials")
		}
	}
	if err := applyAuthentication(cfg, nil); err != nil {
		t.Fatal(err)
	}
	if authStore.Default.Authenticator() != nil {
		t.Fatal("disabled authentication was not cleared")
	}
}
