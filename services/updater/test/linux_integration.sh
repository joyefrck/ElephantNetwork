#!/bin/sh
set -eu
[ -f /.dockerenv ] || exit 2
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq dbus polkitd pkexec procps python3 >/dev/null
useradd -m -u 1000 client
mkdir -p /run/dbus
dbus-daemon --system --fork
/usr/lib/polkit-1/polkitd --no-debug > /tmp/polkit.log 2>&1 &
fixture_root=$(mktemp -d /tmp/elephant-updater-XXXXXX)
chmod 755 "$fixture_root"
make_deb() {
  package=$1
  build=$2
  arch=$3
  output=$4
  stage="$fixture_root/package-$package-$build-$arch"
  mkdir -p "$stage/DEBIAN" "$stage/opt/FlClash"
  printf 'Package: %s\nVersion: 2.1.0+%s\nArchitecture: %s\nMaintainer: Private test\nDescription: Private updater fixture\n' "$package" "$build" "$arch" > "$stage/DEBIAN/control"
  printf '#!/bin/sh\nprintf "%s uid=%%s\\n" "$(id -u)" > "$HOME/app-started"\n' "$build" > "$stage/opt/FlClash/FlClash"
  chmod 755 "$stage/opt/FlClash/FlClash"
  dpkg-deb --build --root-owner-group "$stage" "$output" >/dev/null
}
make_deb elephant-network 22101 "$UPDATER_ARCH" "$fixture_root/baseline.deb"
dpkg -i "$fixture_root/baseline.deb" >/dev/null
make_deb elephant-network 22102 "$UPDATER_ARCH" "$fixture_root/target.deb"
make_deb wrong-client 22102 "$UPDATER_ARCH" "$fixture_root/wrong.deb"
id=0123456789abcdef0123456789abcdef
task="$fixture_root/$id"
mkdir "$task"
chown client:client "$task"
printf 'retained account\n' > /home/client/account.json
chown client:client /home/client/account.json
write_task() {
  cp "$1" "$task/installer.deb"
  python3 - "$task" "$UPDATER_ARCH" <<'PY'
import hashlib,json,os,sys
root,arch=sys.argv[1:]
path=root+'/installer.deb'
data={'id':os.path.basename(root),'file':path,'app':'/opt/FlClash/FlClash','pid':999999,'uid':1000,'release':{'version':'2.1.0','build_number':22102,'platform':'linux','arch':arch,'file_size':os.path.getsize(path),'sha256':hashlib.sha256(open(path,'rb').read()).hexdigest()}}
json.dump(data,open(root+'/install.json','w'))
PY
  chown -R client:client "$task"
}
write_task "$fixture_root/wrong.deb"
if su -s /bin/sh client -c "/updater --prepare '$task/install.json'"; then exit 1; fi
write_task "$fixture_root/target.deb"
su -s /bin/sh client -c "/updater --prepare '$task/install.json'"
if timeout 20s su -s /bin/sh client -c "/updater --install '$task/install.json'"; then exit 1; fi
[ "$(dpkg-query -W -f='${Version}' elephant-network)" = '2.1.0+22101' ]
[ "$(cat /home/client/account.json)" = 'retained account' ]
cat > /etc/polkit-1/rules.d/49-elephant-updater-test.rules <<'RULES'
polkit.addRule(function(action, subject) {
  if (action.id == 'org.freedesktop.policykit.exec' && subject.user == 'client' && action.lookup('program') == '/usr/bin/apt-get') {
    return polkit.Result.YES;
  }
});
RULES
sleep 1
su -s /bin/sh client -c "/updater --install '$task/install.json'"
[ "$(dpkg-query -W -f='${Version}' elephant-network)" = '2.1.0+22102' ]
[ "$(cat /home/client/account.json)" = 'retained account' ]
for attempt in 1 2 3 4 5; do
  [ "$(cat /home/client/app-started 2>/dev/null || true)" != '22102 uid=1000' ] || break
  sleep 1
done
[ "$(cat /home/client/app-started)" = '22102 uid=1000' ]
python3 - "$task/install-state.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['state']=='installed'
PY
printf 'Linux DEB identity, denied authorization, build upgrade and user restart passed\n'
