package core

import (
	"context"
	"net/http"
	"testing"
	"time"
)

func TestProbeCancelBeforeDispatch(t *testing.T) {
	cancelProbeTask("cancel-before-start")
	ctx, release := beginProbeTask("cancel-before-start")
	defer release()
	if ctx.Err() != context.Canceled {
		t.Fatal("late task survived cancellation")
	}
}

func TestRouteChangeCancelsRunningProbeTask(t *testing.T) {
	ctx, release := beginProbeTask("route-cancel")
	defer release()
	bumpRouteEpoch()
	if ctx.Err() != context.Canceled {
		t.Fatal("route change left old task running")
	}
}

func TestExplicitProbeCancelClosesHttpRequest(t *testing.T) {
	withProbeProxies(t, "DIRECT")
	started, stopped := make(chan struct{}), make(chan struct{})
	server := probeServer(t, func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-r.Context().Done()
		close(stopped)
	})
	done := make(chan *OutboundIpResult, 1)
	go func() {
		done <- handleOutboundIp(&OutboundIpParams{TaskID: "cancel-http", ProxyName: "DIRECT", Urls: []string{server.URL}, Timeout: 10000})
	}()
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("request did not start")
	}
	cancelProbeTask("cancel-http")
	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("probe did not cancel")
	}
	select {
	case <-stopped:
	case <-time.After(time.Second):
		t.Fatal("HTTP request remained active")
	}
}
