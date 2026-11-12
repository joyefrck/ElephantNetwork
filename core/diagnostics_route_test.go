package core

import (
	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"testing"
)

func TestDiagnosticRouteInvalidatesOnlyWhenSelectionMoves(t *testing.T) {
	recordRoutes(t)
	members := []constant.Proxy{namedProxy("node-a"), namedProxy("node-b")}
	health := provider.NewHealthCheck(members, "", 0, 0, true, nil)
	pd, err := provider.NewCompatibleProvider("test", members, health)
	if err != nil {
		t.Fatal(err)
	}
	selector, err := outboundgroup.NewSelector(outboundgroup.GroupCommonOption{Name: "Proxy"}, outboundgroup.SelectorOption{}, nil, []cp.ProxyProvider{pd})
	if err != nil {
		t.Fatal(err)
	}
	tunnel.UpdateProxies(map[string]constant.Proxy{"Proxy": adapter.NewProxy(selector), "node-a": members[0], "node-b": members[1]}, nil)
	t.Cleanup(func() { tunnel.UpdateProxies(nil, nil) })
	initial := handleWatchRoute(true, 1)
	change := func(name string) {
		done := make(chan string, 1)
		handleChangeProxy(&ChangeProxyParams{GroupName: "Proxy", ProxyName: name}, func(result string) { done <- result })
		if result := <-done; result != "" {
			t.Fatal(result)
		}
	}
	change("node-a")
	if routeState() != initial {
		t.Fatal("unchanged selection invalidated route")
	}
	change("node-b")
	moved := routeState()
	if moved.CoreEpoch != initial.CoreEpoch || moved.RouteVersion != initial.RouteVersion+1 {
		t.Fatalf("bad stamp: %+v", moved)
	}
	if got := resolveExit("example.com:443", "Proxy"); got != exitName(members[1]) {
		t.Fatalf("actual exit: %s", got)
	}
	hit := RouteHit{Host: "example.com:443", Proxy: "Proxy", Exit: exitName(members[1])}
	if !handleCheckRoutes(&CheckRoutesParams{Routes: [][]RouteHit{{hit}}}).Held[0] {
		t.Fatal("current route not held")
	}
	change("node-a")
	if handleCheckRoutes(&CheckRoutesParams{Routes: [][]RouteHit{{hit}}}).Held[0] {
		t.Fatal("old route held after switch")
	}
}

func TestDiagnosticWatchHonorsLatestArrival(t *testing.T) {
	recordRoutes(t)
	handleWatchRoute(true, 4)
	handleWatchRoute(false, 5)
	handleWatchRoute(true, 3)
	currentRoute.mu.Lock()
	watched, poll := currentRoute.watched, currentRoute.stopPoll
	currentRoute.mu.Unlock()
	if watched || poll != nil {
		t.Fatal("older watch restarted route polling")
	}
}
