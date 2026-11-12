//go:build android

package mobile

import "core"

func InvokeMethod(data string, handler ResultHandler) {
	if handler == nil {
		return
	}
	core.InvokeMethod(data, func(result []byte) { _ = handler.OnResult(result) })
}
func StartTun(fd int32, handler TunHandler, stack, address, dns string) bool {
	if handler == nil {
		return false
	}
	return core.StartTun(tunCallbacks{handler}, int(fd), stack, address, dns)
}
func QuickSetup(initParams, setupParams string, handler ResultHandler) {
	if handler == nil {
		return
	}
	core.QuickSetup(initParams, setupParams, func(message string) { _ = handler.OnResult([]byte(message)) })
}
func SetEventListener(handler ResultHandler) {
	if handler == nil {
		core.SetEventListener(nil)
		return
	}
	core.SetEventListener(func(data []byte) { _ = handler.OnResult(data) })
}
func StopTun()                              { core.StopTun() }
func StartListener()                        { core.StartListener() }
func StopListener()                         { core.StopListener() }
func ForceGC()                              { core.ForceGC() }
func UpdateDns(value string)                { core.UpdateDns(value) }
func ResetNetwork()                         { core.ResetNetwork() }
func GetTraffic(onlyProxy bool) string      { return core.GetTraffic(onlyProxy) }
func GetTotalTraffic(onlyProxy bool) string { return core.GetTotalTraffic(onlyProxy) }
