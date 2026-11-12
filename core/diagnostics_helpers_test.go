package core

import (
	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outbound"
	"github.com/metacubex/mihomo/constant"
	"net"
	"testing"
)

func namedProxy(name string) constant.Proxy {
	return adapter.NewProxy(outbound.NewDirectWithOption(outbound.DirectOption{Name: name}))
}
func stampRoute(epoch, version uint64) {
	currentRoute.mu.Lock()
	defer currentRoute.mu.Unlock()
	currentRoute.epoch, currentRoute.version = epoch, version
}
func clearRoute() {
	stopRouteWatch()
	currentRoute.mu.Lock()
	defer currentRoute.mu.Unlock()
	currentRoute.epoch, currentRoute.version, currentRoute.watchSeq = 0, 0, 0
	currentRoute.picks, currentRoute.providerVersions, currentRoute.ruleSets = nil, nil, nil
}
func recordRoutes(t *testing.T) { t.Helper(); clearRoute(); t.Cleanup(clearRoute) }

func blackHoleServer(t *testing.T) net.Addr {
	t.Helper()

	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}

	var conns []net.Conn
	accepting := make(chan struct{})
	go func() {
		defer close(accepting)
		for {
			conn, err := listener.Accept()
			if err != nil {
				return
			}
			conns = append(conns, conn)
		}
	}()

	t.Cleanup(func() {
		_ = listener.Close()

		<-accepting
		for _, conn := range conns {
			_ = conn.Close()
		}
	})

	return listener.Addr()
}
