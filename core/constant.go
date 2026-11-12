package core

import (
	"encoding/json"
	"github.com/metacubex/mihomo/adapter/provider"
	P "github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"net/netip"
	"time"
)

type InitParams struct {
	HomeDir string `json:"home-dir"`
	Version int    `json:"version"`
}

type SetupParams struct {
	SelectedMap      map[string]string `json:"selected-map"`
	TestURL          string            `json:"test-url"`
	DelayTestTimeout int64             `json:"delay-test-timeout"`
}

type UpdateParams struct {
	Secret             *string            `json:"secret"`
	Authentication     *[]string          `json:"authentication"`
	Tun                *tunSchema         `json:"tun"`
	AllowLan           *bool              `json:"allow-lan"`
	MixedPort          *int               `json:"mixed-port"`
	FindProcessMode    *P.FindProcessMode `json:"find-process-mode"`
	Mode               *tunnel.TunnelMode `json:"mode"`
	LogLevel           *log.LogLevel      `json:"log-level"`
	IPv6               *bool              `json:"ipv6"`
	Sniffing           *bool              `json:"sniffing"`
	TCPConcurrent      *bool              `json:"tcp-concurrent"`
	ExternalController *string            `json:"external-controller"`
	Interface          *string            `json:"interface-name"`
	UnifiedDelay       *bool              `json:"unified-delay"`
	GeoAutoUpdate      *bool              `json:"geo-auto-update"`
	GeoUpdateInterval  *int               `json:"geo-update-interval"`
	DelayTestTimeout   *int64             `json:"delay-test-timeout"`
}

type tunSchema struct {
	Enable                bool               `yaml:"enable" json:"enable"`
	Device                *string            `yaml:"device" json:"device"`
	Stack                 *constant.TUNStack `yaml:"stack" json:"stack"`
	DNSHijack             *[]string          `yaml:"dns-hijack" json:"dns-hijack"`
	AutoRoute             *bool              `yaml:"auto-route" json:"auto-route"`
	RouteAddress          *[]netip.Prefix    `yaml:"route-address" json:"route-address,omitempty"`
	DNSMode               *string            `json:"dns-mode"`
	MTU                   *uint32            `json:"mtu"`
	StrictRoute           *bool              `json:"strict-route"`
	AutoDetectInterface   *bool              `json:"auto-detect-interface"`
	RouteExcludeAddress   *[]netip.Prefix    `json:"route-exclude-address"`
	IncludeInterface      *[]string          `json:"include-interface"`
	ExcludeInterface      *[]string          `json:"exclude-interface"`
	IncludeUID            *[]uint32          `json:"include-uid"`
	ExcludeUID            *[]uint32          `json:"exclude-uid"`
	ExcludeSrcPort        *[]uint16          `json:"exclude-src-port"`
	ExcludeDstPort        *[]uint16          `json:"exclude-dst-port"`
	UDPTimeout            *int64             `json:"udp-timeout"`
	DisableICMPForwarding *bool              `json:"disable-icmp-forwarding"`
	GSO                   *bool              `json:"gso"`
	CongestionController  *string            `json:"congestion-controller"`
}

type ChangeProxyParams struct {
	GroupName string `json:"group-name"`
	ProxyName string `json:"proxy-name"`
}

type TestDelayParams struct {
	ProxyName string `json:"proxy-name"`
	TestUrl   string `json:"test-url"`
	Timeout   int64  `json:"timeout"`
}

type Traffic struct {
	Up   int64 `json:"up"`
	Down int64 `json:"down"`
}

type ExternalProvider struct {
	Name             string                     `json:"name"`
	Type             string                     `json:"type"`
	VehicleType      string                     `json:"vehicle-type"`
	Count            int                        `json:"count"`
	Path             string                     `json:"path"`
	UpdateAt         time.Time                  `json:"update-at"`
	SubscriptionInfo *provider.SubscriptionInfo `json:"subscription-info"`
}

type ProxiesData struct {
	Proxies map[string]constant.Proxy `json:"proxies"`
	All     []string                  `json:"all"`
}

const (
	probeCancelMethod     CoreMethod = "probe.cancel"
	routeWatchMethod      CoreMethod = "route.watch"
	routeCheckMethod      CoreMethod = "route.check"
	probeOutboundIpMethod CoreMethod = "probe.outboundIp"
	probeServicesMethod   CoreMethod = "probe.services"

	messageMethod             CoreMethod = "message"
	coreInitMethod            CoreMethod = "core.init"
	coreInitializedMethod     CoreMethod = "core.initialized"
	coreGcMethod              CoreMethod = "core.gc"
	coreShutdownMethod        CoreMethod = "core.shutdown"
	configValidateMethod      CoreMethod = "config.validate"
	configUpdateMethod        CoreMethod = "config.update"
	proxyListMethod           CoreMethod = "proxy.list"
	proxySelectMethod         CoreMethod = "proxy.select"
	trafficCurrentMethod      CoreMethod = "traffic.current"
	trafficTotalMethod        CoreMethod = "traffic.total"
	trafficResetMethod        CoreMethod = "traffic.reset"
	proxyTestDelayMethod      CoreMethod = "proxy.testDelay"
	connectionListMethod      CoreMethod = "connection.list"
	connectionCloseAllMethod  CoreMethod = "connection.closeAll"
	connectionResetMethod     CoreMethod = "connection.reset"
	dnsClearCacheMethod       CoreMethod = "dns.clearCache"
	networkChangedMethod      CoreMethod = "network.changed"
	configUpdateRuntimeMethod CoreMethod = "config.updateRuntime"
	connectionCloseMethod     CoreMethod = "connection.close"
	providerListMethod        CoreMethod = "provider.list"
	providerGetMethod         CoreMethod = "provider.get"
	geoCountryCodeMethod      CoreMethod = "geo.countryCode"
	coreMemoryMethod          CoreMethod = "core.memory"
	geoUpdateMethod           CoreMethod = "geo.update"
	providerUpdateMethod      CoreMethod = "provider.update"
	providerSideLoadMethod    CoreMethod = "provider.sideLoad"
	logStartMethod            CoreMethod = "log.start"
	logStopMethod             CoreMethod = "log.stop"
	listenerStartMethod       CoreMethod = "listener.start"
	listenerStopMethod        CoreMethod = "listener.stop"
	dnsUpdateSystemMethod     CoreMethod = "dns.updateSystem"
	coreCrashMethod           CoreMethod = "core.crash"
	configSetupMethod         CoreMethod = "config.setup"
	configReadMethod          CoreMethod = "config.read"
	profileClearEffectMethod  CoreMethod = "profile.clearEffect"
)

type RouteState struct {
	CoreEpoch    uint64 `json:"core-epoch"`
	RouteVersion uint64 `json:"route-version"`
}

type WatchParams struct {
	Watch bool `json:"watch"`
}

type CoreMethod string

const RouteChangedMessage MessageType = "routeChanged"

type MessageType string

type Delay struct {
	Url   string `json:"url"`
	Name  string `json:"name"`
	Value int32  `json:"value"`
}

type Message struct {
	Type MessageType `json:"type"`
	Data interface{} `json:"data"`
}

const (
	LogMessage       MessageType = "log"
	DelayMessage     MessageType = "delay"
	RequestMessage   MessageType = "request"
	LoadedMessage    MessageType = "loaded"
	GeoUpdateMessage MessageType = "geoUpdate"
)

type GeoUpdateStatus struct {
	Type     string `json:"type"`
	Updating bool   `json:"updating"`
	Skipped  bool   `json:"skipped,omitempty"`
	Error    string `json:"error,omitempty"`
}

func (message *Message) Json() (string, error) {
	data, err := json.Marshal(message)
	return string(data), err
}

type PathParams struct {
	Path    string `json:"path"`
	Runtime bool   `json:"runtime"`
}
type NameParams struct {
	Name string `json:"name"`
}
type ConnectionParams struct {
	ID string `json:"id"`
}
type CountryParams struct {
	IP string `json:"ip"`
}
type GeoParams struct {
	Type string `json:"type"`
}
type ProfileEffectParams struct {
	ProfileID int64 `json:"profile-id"`
}
type TrafficParams struct {
	OnlyStatisticsProxy bool `json:"only-statistics-proxy"`
}
