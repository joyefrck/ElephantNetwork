set -euo pipefail

version_line=$(sed -nE 's/^version: (.+)/\1/p' pubspec.yaml)
version=${version_line%%+*}
build=${version_line#*+}
package=''
app=''
core=''

if [ "$PACKAGE_PLATFORM" = macos ]; then
  package=$(find "$PWD/dist" -type f -name '*.dmg')
  test "$(printf '%s\n' "$package" | wc -l | tr -d ' ')" = 1
  hdiutil verify "$package"
  mountpoint=$(mktemp -d "$RUNNER_TEMP/elephant-package.XXXXXX")
  hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$package"
  trap 'hdiutil detach "$mountpoint"' EXIT
  app="$mountpoint/ElephantRoute.app"
  core="$app/Contents/MacOS/FlClashCore"
  codesign --verify --deep --strict "$app"
  expected_arch=arm64
  if [ "$PACKAGE_ARCH" = amd64 ]; then expected_arch=x86_64; fi
  test "$(lipo -archs "$app/Contents/MacOS/ElephantRoute")" = "$expected_arch"
  test "$(lipo -archs "$core")" = "$expected_arch"
  python3 - "$app" "$version" "$build" <<'PY'
import pathlib
import plistlib
import sys

info = plistlib.loads((pathlib.Path(sys.argv[1]) / 'Contents/Info.plist').read_bytes())
assert info['CFBundleShortVersionString'] == sys.argv[2], info
assert info['CFBundleVersion'] == sys.argv[3], info
assert info['CFBundleIdentifier'] == 'com.elphantroute.elephantNetwork', info
assert info['LSMinimumSystemVersion'] == '12.0', info
PY
else
  package=$(find "$PWD/dist" -type f -name '*.deb')
  test "$(printf '%s\n' "$package" | wc -l | tr -d ' ')" = 1
  test "$(dpkg-deb -f "$package" Package)" = elephant-network
  test "$(dpkg-deb -f "$package" Architecture)" = amd64
  deb_version=$(dpkg-deb -f "$package" Version)
  test "$deb_version" = "$version_line"
  sudo apt-get install -y "$package"
  app=/opt/FlClash/FlClash
  core=/opt/FlClash/FlClashCore
  test -x "$app"
  test -x "$core"
  file "$app" | grep -q 'x86-64'
  file "$core" | grep -q 'x86-64'
  desktop-file-validate /usr/share/applications/FlClash.desktop
  ldd "$app" | tee "$RUNNER_TEMP/elephant-app-libraries.log"
  ! grep -q 'not found' "$RUNNER_TEMP/elephant-app-libraries.log"
  while IFS= read -r library; do
    ldd "$library" > "$RUNNER_TEMP/elephant-library.log" 2>&1 || true
    if grep -q 'not found' "$RUNNER_TEMP/elephant-library.log"; then
      cat "$RUNNER_TEMP/elephant-library.log"
      exit 1
    fi
  done < <(find /opt/FlClash/lib -type f -name '*.so')
fi

python3 .github/scripts/verify_core_runtime.py "$core" "$package.core-acceptance.json"

if [ "$PACKAGE_PLATFORM" = linux ]; then
  set +e
  dbus-run-session -- xvfb-run -a timeout 15s "$app" > "$RUNNER_TEMP/elephant-app-startup.log" 2>&1
  status=$?
  set -e
  cat "$RUNNER_TEMP/elephant-app-startup.log"
  test "$status" = 124 -o "$status" = 0
  ! grep -Eiq 'Unhandled Exception|Segmentation fault|error while loading shared libraries' "$RUNNER_TEMP/elephant-app-startup.log"
  sudo apt-get remove -y elephant-network
  test ! -e "$app"
fi

python3 - "$package" "$version_line" <<'PY'
import hashlib
import json
import os
import pathlib
import subprocess
import sys

package = pathlib.Path(sys.argv[1])
digest = hashlib.sha256(package.read_bytes()).hexdigest()
package.with_suffix(package.suffix + '.sha256').write_text(f'{digest}  {package.name}\n')
metadata = {
    'source_commit': os.environ.get('GITHUB_SHA'),
    'mihomo_revision': subprocess.check_output(['git', '-C', 'core/Clash.Meta', 'rev-parse', 'HEAD'], text=True).strip(),
    'version': sys.argv[2],
    'platform': os.environ['PACKAGE_PLATFORM'],
    'architecture': os.environ['PACKAGE_ARCH'],
    'package_bytes': package.stat().st_size,
    'sha256': digest,
    'core_acceptance': json.loads(pathlib.Path(str(package) + '.core-acceptance.json').read_text()),
}
package.with_suffix(package.suffix + '.build.json').write_text(json.dumps(metadata, indent=2) + '\n')
print(json.dumps(metadata, indent=2))
PY
