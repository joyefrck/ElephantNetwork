package core

import (
	"bytes"
	"encoding/json"
	"fmt"
	"runtime"
)

type MethodCall struct {
	ID        string          `json:"id,omitempty"`
	Method    CoreMethod      `json:"method"`
	Arguments json.RawMessage `json:"arguments"`
}

func (call MethodCall) decodeArguments(target any) error {
	if len(call.Arguments) == 0 || string(call.Arguments) == "null" {
		return fmt.Errorf("missing arguments")
	}
	if raw := bytes.TrimSpace(call.Arguments); len(raw) == 0 || raw[0] != '{' {
		return fmt.Errorf("arguments must be an object")
	}
	return json.Unmarshal(call.Arguments, target)
}

func decodeMethodArguments(call *MethodCall, response MethodResponse, target any) bool {
	if err := call.decodeArguments(target); err != nil {
		response.failure(
			"invalid_arguments",
			fmt.Sprintf("invalid arguments for %s: %v", call.Method, err),
			nil,
		)
		return false
	}
	return true
}

type MethodError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Details any    `json:"details"`
}

type MethodResponse struct {
	File   string       `json:"file,omitempty"`
	ID     string       `json:"id,omitempty"`
	Result any          `json:"result"`
	Error  *MethodError `json:"error,omitempty"`
	reply  func([]byte)
}

func (response MethodResponse) JSON() ([]byte, error) {
	data, err := json.Marshal(response)
	if err == nil {
		return data, nil
	}
	return json.Marshal(MethodResponse{ID: response.ID, Error: &MethodError{
		Code: "internal_error", Message: "Cannot encode Core response: " + err.Error(),
	}})
}

func (response MethodResponse) send() {
	data, err := response.JSON()
	if err != nil {
		logError("Cannot encode Core response: %v", err)
		return
	}
	if response.reply != nil {
		response.reply(spillResponse(response.ID, data))
	}
}

func (response MethodResponse) success(result any) {
	response.Result = result
	response.Error = nil
	response.send()
}

func (response MethodResponse) failure(code, message string, details any) {
	response.Result = nil
	response.Error = &MethodError{
		Code:    code,
		Message: message,
		Details: details,
	}
	response.send()
}

func (response MethodResponse) command(message string) {
	if message != "" {
		response.failure("core_error", message, nil)
		return
	}
	response.success(nil)
}

func (response MethodResponse) action(applied bool) {
	if !applied {
		response.failure("core_error", "Core command was not applied", nil)
		return
	}
	response.success(nil)
}

func (response MethodResponse) notImplemented(method CoreMethod) {
	response.failure(
		"not_implemented",
		fmt.Sprintf("unknown method: %s", method),
		nil,
	)
}

func handleMethodCall(call *MethodCall, response MethodResponse) {
	if call.Method == coreCrashMethod {
		handleCrash()
		return
	}
	defer func() {
		if r := recover(); r != nil {
			buf := make([]byte, 4096)
			n := runtime.Stack(buf, false)
			logError("panic in handleMethodCall(%s): %v\n%s", call.Method, r, buf[:n])
			response.failure("internal_error", fmt.Sprintf("internal panic: %v", r), nil)
		}
	}()
	switch call.Method {
	case configUpdateRuntimeMethod:
		var sections map[string]any
		if !decodeMethodArguments(call, response, &sections) {
			return
		}
		response.command(handleUpdateRuntimeConfig(sections))
		return
	case dnsClearCacheMethod:
		handleClearDnsCache()
		response.success(nil)
	case networkChangedMethod:
		handleResetNetwork()
		response.success(nil)

	case coreInitMethod:
		params := InitParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		response.action(handleInitClash(&params))
		return
	case coreInitializedMethod:
		response.success(handleGetIsInit())
		return
	case coreGcMethod:
		handleForceGC()
		response.success(nil)
		return
	case coreShutdownMethod:
		response.action(handleShutdown())
		return
	case configValidateMethod:
		path := PathParams{}
		if !decodeMethodArguments(call, response, &path) {
			return
		}
		response.command(validateProfileConfig(path.Path, path.Runtime))
		return
	case configUpdateMethod:
		params := UpdateParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		response.command(handleUpdateConfig(&params))
		return
	case configSetupMethod:
		params := defaultSetupParams()
		if !decodeMethodArguments(call, response, params) {
			return
		}
		response.command(handleSetupConfig(params))
		return
	case proxyListMethod:
		response.success(handleGetProxies())
		return
	case proxySelectMethod:
		params := ChangeProxyParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		handleChangeProxy(&params, func(value string) {
			response.command(value)
		})
		return
	case trafficCurrentMethod:
		params := TrafficParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		response.success(handleGetTraffic(params.OnlyStatisticsProxy))
		return
	case trafficTotalMethod:
		params := TrafficParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		response.success(handleGetTotalTraffic(params.OnlyStatisticsProxy))
		return
	case trafficResetMethod:
		handleResetTraffic()
		response.success(nil)
		return
	case proxyTestDelayMethod:
		params := TestDelayParams{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		handleAsyncTestDelay(&params, func(value *Delay) {
			response.success(value)
		})
		return
	case connectionListMethod:
		response.success(handleGetConnections())
		return
	case connectionCloseAllMethod:
		response.action(handleCloseConnections())
		return
	case connectionResetMethod:
		response.action(handleResetConnections())
		return
	case configReadMethod:
		path := PathParams{}
		if !decodeMethodArguments(call, response, &path) {
			return
		}
		config, err := handleGetConfig(path.Path)
		if err != nil {
			response.failure("core_error", err.Error(), nil)
			return
		}
		response.success(config)
		return
	case connectionCloseMethod:
		id := ConnectionParams{}
		if !decodeMethodArguments(call, response, &id) {
			return
		}
		response.action(handleCloseConnection(id.ID))
		return
	case providerListMethod:
		response.success(handleGetExternalProviders())
		return
	case providerGetMethod:
		externalProviderName := NameParams{}
		if !decodeMethodArguments(call, response, &externalProviderName) {
			return
		}
		response.success(handleGetExternalProvider(externalProviderName.Name))
		return
	case geoUpdateMethod:
		geoType := GeoParams{}
		if !decodeMethodArguments(call, response, &geoType) {
			return
		}
		handleUpdateGeoData(geoType.Type)
		response.success(nil)
		return
	case providerUpdateMethod:
		providerName := NameParams{}
		if !decodeMethodArguments(call, response, &providerName) {
			return
		}
		handleUpdateExternalProvider(providerName.Name, func(value string) {
			response.command(value)
		})
		return
	case providerSideLoadMethod:
		params := map[string]string{}
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		providerName := params["name"]
		data := params["data"]
		handleSideLoadExternalProvider(providerName, []byte(data), func(value string) {
			response.command(value)
		})
		return
	case logStartMethod:
		handleStartLog()
		response.success(nil)
		return
	case logStopMethod:
		handleStopLog()
		response.success(nil)
		return
	case listenerStartMethod:
		response.action(handleStartListener())
		return
	case listenerStopMethod:
		response.action(handleStopListener())
		return
	case geoCountryCodeMethod:
		ip := CountryParams{}
		if !decodeMethodArguments(call, response, &ip) {
			return
		}
		handleGetCountryCode(ip.IP, func(value string) {
			response.success(value)
		})
		return
	case coreMemoryMethod:
		handleGetMemory(func(value uint64) {
			response.success(value)
		})
		return
	case profileClearEffectMethod:
		var params ProfileEffectParams
		if !decodeMethodArguments(call, response, &params) {
			return
		}
		handleClearEffect(params.ProfileID, response)
		return
	default:
		if !handlePlatformMethodCall(call, response) {
			response.notImplemented(call.Method)
		}
	}
}
