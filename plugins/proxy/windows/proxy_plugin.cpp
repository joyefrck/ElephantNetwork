#include <winsock2.h>
#include <ws2ipdef.h>
#include <iphlpapi.h>
#include "proxy_owner.h"
#include "proxy_plugin.h"

#include <windows.h>

#include <WinInet.h>
#include <Ras.h>
#include <RasError.h>
#include <algorithm>
#include <functional>
#include <string>
#include <vector>

#pragma comment(lib, "wininet")
#pragma comment(lib, "Rasapi32")
#pragma comment(lib, "iphlpapi")
#pragma comment(lib, "advapi32")

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>

namespace
{

constexpr int kMinProxyPort = 1;
constexpr int kMaxProxyPort = 65535;

std::wstring Utf8ToWide(const std::string& value)
{
  if (value.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0)
  {
    return std::wstring(value.begin(), value.end());
  }
  std::wstring result(size, L'\0');
  MultiByteToWideChar(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()),
      result.data(), size);
  return result;
}

std::wstring BuildBypassList(const flutter::EncodableList& bypassDomain)
{
  std::wstring bypassList;
  for (const auto& domain : bypassDomain)
  {
    const auto& value = std::get<std::string>(domain);
    if (!bypassList.empty())
    {
      bypassList += L";";
    }
    bypassList += Utf8ToWide(value);
  }
  return bypassList;
}

bool IsStringList(const flutter::EncodableList& values)
{
  return std::all_of(
      values.begin(), values.end(), [](const auto& value)
      {
        return std::holds_alternative<std::string>(value);
      });
}

bool SetOptionsForConnection(
    INTERNET_PER_CONN_OPTION_LIST& list,
    LPTSTR connection)
{
  list.pszConnection = connection;
  return InternetSetOption(
      nullptr,
      INTERNET_OPTION_PER_CONNECTION_OPTION,
      &list,
      sizeof(list)) != FALSE;
}

bool ForEachConnection(const std::function<bool(LPTSTR)>& action)
{
  bool success = action(nullptr);
  DWORD size = sizeof(RASENTRYNAME);
  DWORD count = 0;
  std::vector<RASENTRYNAME> entries(1);
  entries[0].dwSize = sizeof(RASENTRYNAME);
  auto result = RasEnumEntries(nullptr, nullptr, entries.data(), &size, &count);
  if (result == ERROR_BUFFER_TOO_SMALL)
  {
    entries.resize(size / sizeof(RASENTRYNAME));
    for (auto& entry : entries) entry.dwSize = sizeof(RASENTRYNAME);
    result = RasEnumEntries(nullptr, nullptr, entries.data(), &size, &count);
  }
  if (result != ERROR_SUCCESS) return false;
  for (DWORD index = 0; index < count; ++index) success = action(entries[index].szEntryName) && success;
  return success;
}

bool ApplyOptionsToConnections(INTERNET_PER_CONN_OPTION_LIST& list)
{
  return ForEachConnection([&list](LPTSTR connection)
  {
    return SetOptionsForConnection(list, connection);
  });
}

bool NotifySettingsChanged()
{
  const bool changed = InternetSetOption(
      nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0) != FALSE;
  const bool refreshed = InternetSetOption(
      nullptr, INTERNET_OPTION_REFRESH, nullptr, 0) != FALSE;
  return changed && refreshed;
}

const wchar_t* kOwnerKey = L"Software\\com.elephantroute\\ElephantNetwork\\ProxyOwner";

std::wstring ReadProxyOwner()
{
  DWORD bytes = 0;
  if (RegGetValueW(HKEY_CURRENT_USER, kOwnerKey, L"Server", RRF_RT_REG_SZ,
      nullptr, nullptr, &bytes) != ERROR_SUCCESS || bytes < sizeof(wchar_t) || bytes > 2048)
  {
    return {};
  }
  std::vector<wchar_t> buffer((bytes + sizeof(wchar_t) - 1) / sizeof(wchar_t));
  bytes = static_cast<DWORD>(buffer.size() * sizeof(wchar_t));
  if (RegGetValueW(HKEY_CURRENT_USER, kOwnerKey, L"Server", RRF_RT_REG_SZ,
      nullptr, buffer.data(), &bytes) != ERROR_SUCCESS) return {};
  return std::wstring(buffer.data());
}

bool WriteProxyOwner(const std::wstring& server)
{
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kOwnerKey, 0, nullptr, 0, KEY_SET_VALUE,
      nullptr, &key, nullptr) != ERROR_SUCCESS) return false;
  const auto result = RegSetValueExW(key, L"Server", 0, REG_SZ,
      reinterpret_cast<const BYTE*>(server.c_str()),
      static_cast<DWORD>((server.size() + 1) * sizeof(wchar_t)));
  RegCloseKey(key);
  return result == ERROR_SUCCESS;
}

std::optional<bool> HasTcpListener(ULONG family, int port)
{
  std::vector<BYTE> buffer;
  DWORD size = 0;
  DWORD result = ERROR_INSUFFICIENT_BUFFER;
  for (int attempt = 0; attempt < 3 && result == ERROR_INSUFFICIENT_BUFFER; ++attempt)
  {
    buffer.resize(size);
    result = GetExtendedTcpTable(buffer.empty() ? nullptr : buffer.data(), &size,
        FALSE, family, TCP_TABLE_OWNER_PID_LISTENER, 0);
  }
  if (result != NO_ERROR || buffer.size() < sizeof(DWORD)) return std::nullopt;
  const auto count = *reinterpret_cast<const DWORD*>(buffer.data());
  const size_t rowSize = family == AF_INET ? sizeof(MIB_TCPROW_OWNER_PID) : sizeof(MIB_TCP6ROW_OWNER_PID);
  if (count > (buffer.size() - sizeof(DWORD)) / rowSize) return std::nullopt;
  for (DWORD index = 0; index < count; ++index)
  {
    const auto localPort = family == AF_INET
        ? reinterpret_cast<const MIB_TCPTABLE_OWNER_PID*>(buffer.data())->table[index].dwLocalPort
        : reinterpret_cast<const MIB_TCP6TABLE_OWNER_PID*>(buffer.data())->table[index].dwLocalPort;
    if (_byteswap_ushort(static_cast<USHORT>(localPort)) == port) return true;
  }
  return false;
}

bool ClearOwnedForConnection(LPTSTR connection, const std::wstring& owner, bool onlyReleased)
{
  INTERNET_PER_CONN_OPTION options[2] = {};
  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.pszConnection = connection;
  list.dwOptionCount = 2;
  list.pOptions = options;
  DWORD size = sizeof(list);
  if (!InternetQueryOption(nullptr, INTERNET_OPTION_PER_CONNECTION_OPTION, &list, &size)) return false;
  const auto flags = options[0].Value.dwValue;
  const std::wstring server = options[1].Value.pszValue ? options[1].Value.pszValue : L"";
  if (options[1].Value.pszValue) GlobalFree(options[1].Value.pszValue);
  const auto port = proxy_owner::OwnedPort(server, owner,
      (flags & PROXY_TYPE_PROXY) != 0, (flags & (PROXY_TYPE_AUTO_PROXY_URL | PROXY_TYPE_AUTO_DETECT)) != 0);
  if (!port) return true;
  if (onlyReleased && !proxy_owner::Released(HasTcpListener(AF_INET, *port), HasTcpListener(AF_INET6, *port))) return true;
  options[0].Value.dwValue = (flags & ~PROXY_TYPE_PROXY) | PROXY_TYPE_DIRECT;
  list.dwOptionCount = 1;
  return SetOptionsForConnection(list, connection);
}

void ClearStaleProxy()
{
  const auto owner = ReadProxyOwner();
  if (owner.empty()) return;
  ForEachConnection([&owner](LPTSTR connection)
  {
    return ClearOwnedForConnection(connection, owner, true);
  });
  NotifySettingsChanged();
}

bool startProxy(const int port, const flutter::EncodableList& bypassDomain)
{
  auto url = Utf8ToWide("127.0.0.1:" + std::to_string(port));
  auto bypassList = BuildBypassList(bypassDomain);
  std::vector<INTERNET_PER_CONN_OPTION> options(3);

  INTERNET_PER_CONN_OPTION_LIST list = {};
  list.dwSize = sizeof(list);
  list.dwOptionCount = static_cast<DWORD>(options.size());
  list.pOptions = options.data();

  options[0].dwOption = INTERNET_PER_CONN_FLAGS;
  options[0].Value.dwValue = PROXY_TYPE_DIRECT | PROXY_TYPE_PROXY;

  options[1].dwOption = INTERNET_PER_CONN_PROXY_SERVER;
  options[1].Value.pszValue = url.data();

  options[2].dwOption = INTERNET_PER_CONN_PROXY_BYPASS;
  options[2].Value.pszValue = bypassList.data();

  if (!WriteProxyOwner(url)) return false;
  const bool optionsApplied = ApplyOptionsToConnections(list);
  const bool settingsNotified = NotifySettingsChanged();
  return optionsApplied && settingsNotified;
}

bool stopProxy()
{
  const auto owner = ReadProxyOwner();
  if (owner.empty()) return true;
  const bool optionsApplied = ForEachConnection([&owner](LPTSTR connection)
  {
    return ClearOwnedForConnection(connection, owner, false);
  });
  if (optionsApplied) WriteProxyOwner(L"");
  const bool settingsNotified = NotifySettingsChanged();
  return optionsApplied && settingsNotified;
}

}

namespace proxy
{

  void ProxyPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "proxy",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<ProxyPlugin>(registrar);

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result)
        {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  ProxyPlugin::ProxyPlugin(flutter::PluginRegistrarWindows* registrar)
      : registrar_(registrar)
  {
    ClearStaleProxy();
    window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND window, UINT message, WPARAM wparam, LPARAM lparam)
        {
          return HandleWindowProc(window, message, wparam, lparam);
        });
  }

  ProxyPlugin::~ProxyPlugin()
  {
    if (registrar_ != nullptr)
    {
      registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
    }
  }

  bool ProxyPlugin::IsSessionEnding(UINT message, WPARAM wparam)
  {
    return message == WM_ENDSESSION && wparam != FALSE;
  }

  std::optional<LRESULT> ProxyPlugin::HandleWindowProc(
      HWND window, UINT message, WPARAM wparam, LPARAM lparam)
  {
    if (proxy_applied_ && IsSessionEnding(message, wparam))
    {
      proxy_applied_ = !stopProxy();
    }
    return std::nullopt;
  }

  void ProxyPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name() == "StopProxy")
    {
      const bool stopped = stopProxy();
      proxy_applied_ = proxy_applied_ && !stopped;
      result->Success(stopped);
    }
    else if (method_call.method_name() == "StartProxy")
    {
      auto *arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
      if (arguments == nullptr)
      {
        result->Error("bad_args", "StartProxy requires argument map");
        return;
      }
      auto portIt = arguments->find(flutter::EncodableValue("port"));
      auto bypassDomainIt = arguments->find(flutter::EncodableValue("bypassDomain"));
      if (portIt == arguments->end() || bypassDomainIt == arguments->end())
      {
        result->Error("bad_args", "StartProxy requires port and bypassDomain");
        return;
      }
      auto *port = std::get_if<int>(&portIt->second);
      auto *bypassDomain = std::get_if<flutter::EncodableList>(&bypassDomainIt->second);
      if (port == nullptr || bypassDomain == nullptr)
      {
        result->Error("bad_args", "StartProxy argument types are invalid");
        return;
      }
      if (*port < kMinProxyPort || *port > kMaxProxyPort)
      {
        result->Error("bad_args", "StartProxy port must be between 1 and 65535");
        return;
      }
      if (!IsStringList(*bypassDomain))
      {
        result->Error(
            "bad_args", "StartProxy bypassDomain must contain only strings");
        return;
      }
      proxy_applied_ = true;
      result->Success(startProxy(*port, *bypassDomain));
    }
    else
    {
      result->NotImplemented();
    }
  }
} // namespace proxy
