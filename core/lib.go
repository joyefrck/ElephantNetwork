//go:build android

package core

import (
	"core/platform"
	_ "core/timezone"
	t "core/tun"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
)

type TunCallbacks interface {
	Protect(fd int) bool
	ResolveProcess(protocol int, source, target string, uid int) string
}

type TunHandler struct {
	mu        sync.RWMutex
	listener  *sing_tun.Listener
	callbacks TunCallbacks
}

var (
	tunLock           sync.Mutex
	tunHandler        *TunHandler
	eventListenerMu   sync.RWMutex
	eventListener     func([]byte)
	dnsUpdateRevision atomic.Uint64
	dnsUpdateMu       sync.Mutex
	errBlocked        = errors.New("blocked")
)

func (th *TunHandler) start(fd int, stack, address, dnsAddress string) bool {
	runLock.Lock()
	defer runLock.Unlock()
	th.initHook()
	next := t.Start(fd, stack, address, dnsAddress)
	th.mu.Lock()
	th.listener = next
	th.mu.Unlock()
	if next == nil {
		th.clear()
		return false
	}
	log.Infoln("TUN address: %v", next.Address())
	return true
}

func (th *TunHandler) clear() {
	th.mu.Lock()
	listener := th.listener
	th.listener = nil
	th.callbacks = nil
	th.mu.Unlock()
	dialer.DefaultSocketHook = nil
	process.DefaultPackageNameResolver = nil
	if listener != nil {
		_ = listener.Close()
	}
}

func (th *TunHandler) handleProtect(fd int) {
	th.mu.RLock()
	defer th.mu.RUnlock()
	if th.callbacks != nil {
		th.callbacks.Protect(fd)
	}
}

func (th *TunHandler) handleResolveProcess(source, target net.Addr) string {
	th.mu.RLock()
	defer th.mu.RUnlock()
	if th.callbacks == nil {
		return ""
	}
	var protocol int
	switch source.Network() {
	case "udp", "udp4", "udp6":
		protocol = syscall.IPPROTO_UDP
	case "tcp", "tcp4", "tcp6":
		protocol = syscall.IPPROTO_TCP
	default:
		return ""
	}
	uid := -1
	if version < 29 {
		uid = platform.QuerySocketUidFromProcFs(source, target)
	}
	return th.callbacks.ResolveProcess(protocol, source.String(), target.String(), uid)
}

func (th *TunHandler) initHook() {
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		if platform.ShouldBlockConnection() {
			return errBlocked
		}
		return conn.Control(func(fd uintptr) { th.handleProtect(int(fd)) })
	}
	process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
		source, target := metadata.RawSrcAddr, metadata.RawDstAddr
		if source == nil || target == nil {
			return "", process.ErrInvalidNetwork
		}
		return th.handleResolveProcess(source, target), nil
	}
}

func InvokeMethod(data string, reply func([]byte)) {
	call := &MethodCall{}
	if err := json.Unmarshal([]byte(data), call); err != nil {
		(MethodResponse{reply: reply}).failure("invalid_method_call", err.Error(), nil)
		return
	}
	go handleMethodCall(call, MethodResponse{ID: call.ID, reply: reply})
}

func StartTun(callbacks TunCallbacks, fd int, stack, address, dnsAddress string) bool {
	if fd <= 0 || callbacks == nil {
		return false
	}
	tunLock.Lock()
	if tunHandler != nil {
		tunHandler.clear()
	}
	next := &TunHandler{callbacks: callbacks}
	tunHandler = next
	started := next.start(fd, stack, address, dnsAddress)
	tunLock.Unlock()
	if !started {
		return false
	}
	handleStartListener()
	handleResetConnections()
	return true
}

func StopTun() {
	tunLock.Lock()
	if tunHandler != nil {
		tunHandler.clear()
		tunHandler = nil
	}
	tunLock.Unlock()
	handleStopListener()
}

func QuickSetup(initJSON, setupJSON string, reply func(string)) {
	go func() {
		defer func() {
			if recovered := recover(); recovered != nil {
				logError("Android Core setup panic: %v", recovered)
				reply(fmt.Sprintf("Android Core setup failed: %v", recovered))
			}
		}()
		initParams := InitParams{}
		if err := json.Unmarshal([]byte(initJSON), &initParams); err != nil {
			reply(err.Error())
			return
		}
		params := defaultSetupParams()
		if err := UnmarshalJson([]byte(setupJSON), params); err != nil {
			reply(err.Error())
			return
		}
		if !handleInitClash(&initParams) {
			reply("init failed")
			return
		}
		message := handleSetupConfig(params)
		if message == "" && !handleStartListener() {
			message = "listener start failed"
		}
		reply(message)
	}()
}

func SetEventListener(listener func([]byte)) {
	eventListenerMu.Lock()
	eventListener = listener
	eventListenerMu.Unlock()
}

func sendMessageBatch(messages []Message) {
	eventListenerMu.RLock()
	listener := eventListener
	eventListenerMu.RUnlock()
	if listener == nil {
		return
	}
	arguments, err := json.Marshal(messages)
	if err != nil {
		logError("Cannot encode Core events: %v", err)
		return
	}
	data, err := json.Marshal(MethodCall{Method: messageMethod, Arguments: arguments})
	if err != nil {
		logError("Cannot encode Core event batch: %v", err)
		return
	}
	listener(data)
}

func handleUpdateDns(value string) {
	var addresses []string
	for _, address := range strings.Split(value, ",") {
		if address = strings.TrimSpace(address); address != "" {
			addresses = append(addresses, address)
		}
	}
	revision := dnsUpdateRevision.Add(1)
	go func() {
		dnsUpdateMu.Lock()
		defer dnsUpdateMu.Unlock()
		if revision != dnsUpdateRevision.Load() {
			return
		}
		runLock.Lock()
		defer runLock.Unlock()
		dns.UpdateSystemDNS(addresses)
		dns.FlushCacheWithDefaultResolver()
	}()
}

func handlePlatformMethodCall(call *MethodCall, response MethodResponse) bool {
	if call.Method != dnsUpdateSystemMethod {
		return false
	}
	params := struct {
		Value string `json:"value"`
	}{}
	if decodeMethodArguments(call, response, &params) {
		handleUpdateDns(params.Value)
		response.success(nil)
	}
	return true
}

func StartListener()                        { handleStartListener() }
func StopListener()                         { handleStopListener() }
func ForceGC()                              { handleForceGC() }
func UpdateDns(value string)                { handleUpdateDns(value) }
func ResetNetwork()                         { handleResetNetwork() }
func GetTraffic(onlyProxy bool) string      { return marshalResult(handleGetTraffic(onlyProxy)) }
func GetTotalTraffic(onlyProxy bool) string { return marshalResult(handleGetTotalTraffic(onlyProxy)) }
func marshalResult(value any) string {
	data, err := json.Marshal(value)
	if err != nil {
		logError("Cannot encode Core result: %v", err)
		return ""
	}
	return string(data)
}
