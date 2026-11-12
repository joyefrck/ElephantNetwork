#include "../proxy_owner.h"
#include <cassert>

int main() {
  using proxy_owner::OwnedPort;
  using proxy_owner::Released;
  const std::wstring owner = L"127.0.0.1:2334";
  assert(OwnedPort(owner, owner, true, false) == 2334);
  assert(!OwnedPort(L"127.0.0.1:7890", owner, true, false));
  assert(!OwnedPort(owner, L"", true, false));
  assert(!OwnedPort(owner, owner, false, false));
  assert(!OwnedPort(owner, owner, true, true));
  for (const auto& invalid : {L"127.0.0.1:0", L"127.0.0.1:65536", L"127.0.0.1:2334;https=remote", L"remote:2334"}) {
    assert(!OwnedPort(invalid, invalid, true, false));
  }
  assert(Released(false, false));
  assert(!Released(true, false));
  assert(!Released(false, true));
  assert(!Released(std::nullopt, false));
  assert(!Released(false, std::nullopt));
}
