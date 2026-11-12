package main

import (
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/tunnel"
	"time"
)

func hostDelayTimeout(milliseconds int64) time.Duration {
	if milliseconds <= 0 {
		milliseconds = 5000
	}
	return time.Duration(min(max(milliseconds, 100), 120000)) * time.Millisecond
}

type delayTimeoutProvider interface {
	TestTimeout(string) (time.Duration, bool)
	Proxies() []C.Proxy
}

func configuredTestTimeout(name, url string) (time.Duration, bool) {
	providers := make([]delayTimeoutProvider, 0)
	for _, candidate := range tunnel.ProvidersSnapshot() {
		if provider, ok := candidate.(delayTimeoutProvider); ok {
			providers = append(providers, provider)
		}
	}
	return longestProviderTestTimeout(name, url, providers)
}

func longestProviderTestTimeout(name, url string, providers []delayTimeoutProvider) (time.Duration, bool) {
	var longest time.Duration
	for _, provider := range providers {
		timeout, configured := provider.TestTimeout(url)
		if !configured || timeout <= longest {
			continue
		}
		for _, proxy := range provider.Proxies() {
			if proxy.Name() == name {
				longest = timeout
				break
			}
		}
	}
	return longest, longest > 0
}
