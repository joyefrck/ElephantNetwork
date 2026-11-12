package main

import (
	C "github.com/metacubex/mihomo/constant"
	"testing"
	"time"
)

type timeoutProxy struct {
	C.Proxy
	name string
}

func (p timeoutProxy) Name() string { return p.name }

type timeoutProvider struct {
	duration time.Duration
	url      string
	names    []string
}

func (p timeoutProvider) TestTimeout(url string) (time.Duration, bool) {
	return p.duration, url == p.url
}
func (p timeoutProvider) Proxies() []C.Proxy {
	var proxies []C.Proxy
	for _, name := range p.names {
		proxies = append(proxies, timeoutProxy{name: name})
	}
	return proxies
}

func TestProviderTimeoutUsesLongestMatchingNodeAndURL(t *testing.T) {
	providers := []delayTimeoutProvider{
		timeoutProvider{time.Second, "https://test", []string{"node"}},
		timeoutProvider{8 * time.Second, "https://test", []string{"node"}},
		timeoutProvider{30 * time.Second, "https://other", []string{"node"}},
		timeoutProvider{40 * time.Second, "https://test", []string{"other"}},
	}
	if got, ok := longestProviderTestTimeout("node", "https://test", providers); !ok || got != 8*time.Second {
		t.Fatalf("got %v %v", got, ok)
	}
	if _, ok := longestProviderTestTimeout("absent", "https://test", providers); ok {
		t.Fatal("unrelated node inherited a timeout")
	}
}

func TestHostDelayTimeoutBounds(t *testing.T) {
	for input, expected := range map[int64]time.Duration{0: 5 * time.Second, -1: 5 * time.Second, 1: 100 * time.Millisecond, 8000: 8 * time.Second, 200000: 120 * time.Second} {
		if got := hostDelayTimeout(input); got != expected {
			t.Errorf("%d: got %v, want %v", input, got, expected)
		}
	}
}
