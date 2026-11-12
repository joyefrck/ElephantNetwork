#pragma once

#include <optional>
#include <string>

namespace proxy_owner {
inline std::optional<int> OwnedPort(
    const std::wstring& current,
    const std::wstring& owner,
    bool enabled,
    bool has_pac) {
  const std::wstring prefix = L"127.0.0.1:";
  if (!enabled || has_pac || owner.empty() || current != owner ||
      current.compare(0, prefix.size(), prefix) != 0 ||
      current.size() <= prefix.size() || current.size() > prefix.size() + 5) {
    return std::nullopt;
  }
  int port = 0;
  for (size_t index = prefix.size(); index < current.size(); ++index) {
    const auto value = current[index];
    if (value < L'0' || value > L'9') return std::nullopt;
    port = port * 10 + value - L'0';
  }
  if (port < 1 || port > 65535) return std::nullopt;
  return port;
}

inline bool Released(std::optional<bool> ipv4, std::optional<bool> ipv6) {
  return ipv4.has_value() && ipv6.has_value() && !*ipv4 && !*ipv6;
}
}
