package core

import (
	"context"
	"net/netip"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/http"
)

const (
	outboundIpConcurrency = 3
	outboundIpStagger     = 800 * time.Millisecond

	outboundIpMaxBody = 4096

	browserUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
)

type OutboundIpParams struct {
	TaskID    string   `json:"task-id"`
	ProxyName string   `json:"proxy-name"`
	Urls      []string `json:"urls"`
	Timeout   int64    `json:"timeout"`
}

type OutboundIpResult struct {
	Url          string     `json:"url"`
	Body         string     `json:"body"`
	Delay        int64      `json:"delay"`
	Chains       []string   `json:"chains"`
	Error        string     `json:"error,omitempty"`
	CoreEpoch    uint64     `json:"core-epoch"`
	RouteVersion uint64     `json:"route-version"`
	Hits         []RouteHit `json:"hits"`
	NodeHits     []RouteHit `json:"node-hits,omitempty"`
}

func handleOutboundIp(params *OutboundIpParams) *OutboundIpResult {
	epoch, version := routeStamp()
	hits := &hitRecorder{}
	failure := func(kind string) *OutboundIpResult {
		return &OutboundIpResult{Error: kind, CoreEpoch: epoch, RouteVersion: version, Hits: hits.list()}
	}
	if len(params.Urls) == 0 {
		return failure(probeErrorFailed)
	}

	parent, releaseTask := beginProbeTask(params.TaskID)
	defer releaseTask()
	timeout := timeoutFromMillis(params.Timeout, defaultProbeTimeout)
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()
	defer claimOutboundIp(epoch, cancel)()

	answers := make(chan *OutboundIpResult, len(params.Urls))
	next := 0
	inFlight := 0
	start := func() {
		if next >= len(params.Urls) || inFlight >= outboundIpConcurrency {
			return
		}
		url := params.Urls[next]
		next++
		inFlight++
		go func() {
			answers <- probeOutboundIpSource(ctx, url, params.ProxyName, timeout, hits)
		}()
	}

	start()

	stagger := time.NewTicker(outboundIpStagger)
	defer stagger.Stop()
	for inFlight > 0 {
		select {
		case answer := <-answers:
			inFlight--
			if answer != nil {
				return answer
			}
			start()
		case <-stagger.C:
			start()
		case <-ctx.Done():
			return failure(probeErrorKind(ctx.Err()))
		}
	}
	return failure(probeErrorFailed)
}

var (
	outboundIpClaimsMu sync.Mutex
	outboundIpClaims   = map[*context.CancelFunc]uint64{}
)

func claimOutboundIp(epoch uint64, cancel context.CancelFunc) func() {
	claim := &cancel
	outboundIpClaimsMu.Lock()
	for other, otherEpoch := range outboundIpClaims {
		if otherEpoch < epoch {
			(*other)()
			delete(outboundIpClaims, other)
		}
	}
	outboundIpClaims[claim] = epoch
	outboundIpClaimsMu.Unlock()
	return func() {
		outboundIpClaimsMu.Lock()
		delete(outboundIpClaims, claim)
		outboundIpClaimsMu.Unlock()
	}
}

func probeOutboundIpSource(ctx context.Context, url string, proxyName string, timeout time.Duration, hits *hitRecorder) *OutboundIpResult {
	result := runProbe(ctx, probeRequest{
		method:    http.MethodGet,
		url:       url,
		proxyName: proxyName,
		headers:   map[string]string{"User-Agent": browserUserAgent},
		timeout:   timeout,
		maxBody:   outboundIpMaxBody,
		recorder:  hits,
	})
	if result == nil || result.Error != "" || result.StatusCode != http.StatusOK || !mentionsIp(result.Body) {
		return nil
	}
	return &OutboundIpResult{
		Url:          url,
		Body:         result.Body,
		Delay:        result.Delay,
		Chains:       result.Chains,
		CoreEpoch:    result.CoreEpoch,
		RouteVersion: result.RouteVersion,
		Hits:         result.hits,
		NodeHits:     nodeHits(result.Chains, proxyName, result.hits),
	}
}

func nodeHits(chains []string, proxyName string, hits []RouteHit) []RouteHit {
	if len(chains) == 0 || chains[0] == proxyName {
		return nil
	}
	node := chains[0]
	var through []RouteHit
	for _, hit := range hits {
		through = withHit(through, RouteHit{Host: hit.Host, Proxy: node, Exit: resolveExit(hit.Host, node)})
	}
	return through
}

var sharedAddressSpace = netip.MustParsePrefix("100.64.0.0/10")

func mentionsIp(body string) bool {
	tokens := strings.FieldsFunc(body, func(r rune) bool {
		return !(r == '.' || r == ':' || '0' <= r && r <= '9' || 'a' <= r && r <= 'z' || 'A' <= r && r <= 'Z')
	})
	for _, token := range tokens {
		addr, err := netip.ParseAddr(token)
		if err != nil {
			continue
		}
		addr = addr.Unmap()
		if addr.IsGlobalUnicast() && !addr.IsPrivate() && !sharedAddressSpace.Contains(addr) {
			return true
		}
	}
	return false
}
