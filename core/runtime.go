package main

import (
	"fmt"
	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/resolver"
	"github.com/metacubex/mihomo/component/sniffer"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant/features"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/ntp/ntp"
	"github.com/metacubex/mihomo/tunnel"
	"go.yaml.in/yaml/v3"
	"net"
	"strconv"
	"time"
)

func handleUpdateRuntimeConfig(sections map[string]any) string {
	runLock.Lock()
	defer runLock.Unlock()
	if currentConfig == nil {
		return "Core configuration is not applied"
	}
	for key := range sections {
		switch key {
		case "dns", "hosts", "ntp", "sniffer":
		default:
			return fmt.Sprintf("unsupported runtime section: %s", key)
		}
	}
	input := make(map[string]any, len(sections)+1)
	for key, value := range sections {
		input[key] = value
	}
	input["ipv6"] = currentConfig.General.IPv6
	data, err := yaml.Marshal(input)
	if err != nil {
		return err.Error()
	}
	raw, err := config.UnmarshalRawConfig(data)
	if err != nil {
		return err.Error()
	}
	general := currentConfig.General
	raw.Mode = general.Mode
	raw.FindProcessMode = general.FindProcessMode
	raw.IPv6 = general.IPv6
	raw.TCPConcurrent = general.TCPConcurrent
	raw.InboundTfo = general.InboundTfo
	raw.InboundMPTCP = general.InboundMPTCP
	raw.KeepAliveIdle = general.KeepAliveIdle
	raw.KeepAliveInterval = general.KeepAliveInterval
	raw.DisableKeepAlive = general.DisableKeepAlive
	raw.UnifiedDelay = general.UnifiedDelay
	raw.Interface = general.Interface
	raw.RoutingMark = general.RoutingMark
	raw.GeodataMode = general.GeodataMode
	raw.GeodataLoader = general.GeodataLoader
	raw.GeositeMatcher = general.GeositeMatcher
	raw.GeoXUrl = config.RawGeoXUrl{
		GeoIp:   general.GeoXUrl.GeoIp,
		GeoSite: general.GeoXUrl.GeoSite,
		Mmdb:    general.GeoXUrl.Mmdb,
		ASN:     general.GeoXUrl.ASN,
	}
	raw.GlobalUA = general.GlobalUA
	raw.ETagSupport = general.ETagSupport
	proxyNames := config.GetProxyNameList()
	defer config.SetProxyNameList(proxyNames)
	parsed, err := config.ParseRawConfig(raw)
	if err != nil {
		return err.Error()
	}
	var dispatcher *sniffer.Dispatcher
	if _, ok := sections["sniffer"]; ok {
		dispatcher, err = sniffer.NewDispatcher(parsed.Sniffer)
		if err != nil {
			return err.Error()
		}
	}
	if _, ok := sections["hosts"]; ok {
		resolver.DefaultHosts = resolver.NewHosts(parsed.Hosts)
		currentConfig.Hosts = parsed.Hosts
	}
	if _, ok := sections["dns"]; ok {
		applyRuntimeDNS(parsed.DNS, currentConfig.General.IPv6)
		currentConfig.DNS = parsed.DNS
	}
	if _, ok := sections["ntp"]; ok {
		if features.Android {
			parsed.NTP.WriteToSystem = false
		}
		applyRuntimeNTP(parsed.NTP)
		currentConfig.NTP = parsed.NTP
	}
	if _, ok := sections["sniffer"]; ok {
		tunnel.UpdateSniffer(dispatcher)
		currentConfig.Sniffer = parsed.Sniffer
	}
	resolver.ResetConnection()
	return ""
}

func applyRuntimeDNS(c *config.DNS, generalIPv6 bool) {
	if !c.Enable {
		resolver.DefaultResolver = nil
		resolver.DefaultHostMapper = nil
		resolver.DefaultService = nil
		resolver.ProxyServerHostResolver = nil
		resolver.DirectHostResolver = nil
		dns.ReCreateServer("", nil, nil)
		return
	}

	ipv6 := c.IPv6 && generalIPv6
	r := dns.NewResolver(dns.Config{
		Main:                 c.NameServer,
		Fallback:             c.Fallback,
		IPv6:                 ipv6,
		IPv6Timeout:          c.IPv6Timeout,
		FallbackIPFilter:     c.FallbackIPFilter,
		FallbackDomainFilter: c.FallbackDomainFilter,
		FallbackLazyQuery:    c.FallbackLazyQuery,
		Default:              c.DefaultNameserver,
		Policy:               c.NameServerPolicy,
		ProxyServer:          c.ProxyServerNameserver,
		ProxyServerPolicy:    c.ProxyServerPolicy,
		DirectServer:         c.DirectNameServer,
		DirectFollowPolicy:   c.DirectFollowPolicy,
		CacheAlgorithm:       c.CacheAlgorithm,
		CacheMaxSize:         c.CacheMaxSize,
	})
	m := dns.NewEnhancer(dns.EnhancerConfig{
		IPv6:          ipv6,
		EnhancedMode:  c.EnhancedMode,
		FakeIPPool:    c.FakeIPPool,
		FakeIPPool6:   c.FakeIPPool6,
		FakeIPSkipper: c.FakeIPSkipper,
		FakeIPTTL:     c.FakeIPTTL,
		UseHosts:      c.UseHosts,
	})

	if old := resolver.DefaultHostMapper; old != nil {
		m.PatchFrom(old.(*dns.ResolverEnhancer))
	}

	s := dns.NewService(r, m)

	resolver.DefaultResolver = r
	resolver.DefaultHostMapper = m
	resolver.DefaultService = s
	resolver.UseSystemHosts = c.UseSystemHosts

	if r.ProxyResolver.Invalid() {
		resolver.ProxyServerHostResolver = r.ProxyResolver
	} else {
		resolver.ProxyServerHostResolver = r.Resolver
	}

	if r.DirectResolver.Invalid() {
		resolver.DirectHostResolver = r.DirectResolver
	} else {
		resolver.DirectHostResolver = r.Resolver
	}

	lc := inbound.NewListenConfig()
	lc.SetRouteMark(c.ListenRoutingMark)
	dns.ReCreateServer(c.Listen, lc, s)
}

func applyRuntimeNTP(c *config.NTP) {
	if c.Enable {
		ntp.ReCreateNTPService(
			net.JoinHostPort(c.Server, strconv.Itoa(c.Port)),
			time.Duration(c.Interval),
			c.DialerProxy,
			tunnel.Tunnel,
			c.WriteToSystem,
		)
	} else {
		ntp.ReCreateNTPService("", 0, "", nil, false)
	}
}
