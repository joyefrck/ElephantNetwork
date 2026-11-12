package main

import (
	"github.com/metacubex/mihomo/config"
	"testing"
)

func TestAndroidCannotWriteSystemTimeOnFullConfigLoads(t *testing.T) {
	for _, android := range []bool{false, true} {
		cfg := &config.Config{NTP: &config.NTP{WriteToSystem: true}}
		applyPlatformLimits(cfg, android)
		if cfg.NTP.WriteToSystem == android {
			t.Fatalf("android=%v, write-to-system=%v", android, cfg.NTP.WriteToSystem)
		}
	}
}
