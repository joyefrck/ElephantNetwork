package core

import (
	"testing"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/listener"
)

func TestRejectedTunStartupPreservesPreviousMode(t *testing.T) {
	if features.Android {
		t.Skip("Android owns the VPN interface")
	}
	previousConfig := currentConfig
	previousRunning := isRunning.Load()
	previousTun := listener.LastTunConf
	defer func() {
		listener.StopListener()
		listener.LastTunConf = previousTun
		currentConfig = previousConfig
		isRunning.Store(previousRunning)
	}()
	var err error
	currentConfig, err = config.ParseRawConfig(config.DefaultRawConfig())
	if err != nil {
		t.Fatal(err)
	}
	currentConfig.General.Tun.FileDescriptor = 1 << 30
	currentConfig.General.Tun.AutoDetectInterface = false
	currentConfig.General.Tun.AutoRoute = false
	isRunning.Store(true)
	if err := updateConfig(&UpdateParams{Tun: &tunSchema{Enable: true}}); err == nil {
		t.Fatal("failed TUN listener was accepted")
	}
	if currentConfig.General.Tun.Enable || listener.GetTunConf().Enable {
		t.Fatal("failed TUN startup changed the selected mode")
	}
	if err := updateConfig(&UpdateParams{Tun: &tunSchema{Enable: false}}); err != nil {
		t.Fatal(err)
	}
}
