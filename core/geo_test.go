package core

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/constant"
)

func TestGeoUpdateUsesNewURLAndWaitsForDownloadFailure(t *testing.T) {
	previousURL, home := geodata.MmdbUrl(), constant.Path.HomeDir()
	t.Cleanup(func() { geodata.SetMmdbUrl(previousURL); constant.SetHomeDir(home) })
	constant.SetHomeDir(t.TempDir())
	started, release := make(chan struct{}), make(chan struct{})
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		<-release
		_, _ = w.Write([]byte("invalid mmdb"))
	}))
	defer server.Close()
	args, _ := json.Marshal(GeoParams{Type: "MMDB", URLs: map[string]string{"mmdb": server.URL}})
	replied := make(chan MethodResponse, 1)
	go handleMethodCall(&MethodCall{Method: geoUpdateMethod, Arguments: args}, MethodResponse{reply: func(data []byte) {
		var response MethodResponse
		_ = json.Unmarshal(data, &response)
		replied <- response
	}})
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		close(release)
		t.Fatal("new URL was not requested")
	}
	if geodata.MmdbUrl() != server.URL {
		close(release)
		t.Fatal("old URL retained")
	}
	select {
	case <-replied:
		close(release)
		t.Fatal("Geo command replied before download finished")
	default:
	}
	if !runLock.TryLock() {
		close(release)
		t.Fatal("network download blocked Core lifecycle")
	}
	runLock.Unlock()
	close(release)
	select {
	case response := <-replied:
		if response.Error == nil || response.Error.Code != "core_error" || !strings.Contains(response.Error.Message, "invalid MMDB") {
			t.Fatalf("download error was lost: %+v", response)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("missing completion reply")
	}
}

func TestGeoURLsRejectInvalidInputBeforeChangingCurrentURL(t *testing.T) {
	old := geodata.MmdbUrl()
	if message := handleUpdateGeoData(&GeoParams{Type: "MMDB", URLs: map[string]string{"mmdb": "file:///tmp/foreign"}}); message == "" {
		t.Fatal("invalid URL accepted")
	}
	if geodata.MmdbUrl() != old {
		t.Fatal("invalid update changed Geo URL")
	}
	if message := handleUpdateGeoData(&GeoParams{Type: "unknown"}); message == "" {
		t.Fatal("unknown resource accepted")
	}
}
