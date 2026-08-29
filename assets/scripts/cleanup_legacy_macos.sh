#!/bin/sh
set -eu

label="com.elphantroute.elephantNetwork.tunhelper"
helper="/Library/PrivilegedHelperTools/ElephantTunHelper"
plist="/Library/LaunchDaemons/com.elphantroute.elephantNetwork.tunhelper.plist"
metadata="/Library/Application Support/ElephantRoute/helper-install.json"

/bin/launchctl bootout "system/${label}" >/dev/null 2>&1 || true
/bin/launchctl bootout system "${plist}" >/dev/null 2>&1 || true
/usr/bin/pkill -f 'Library/Application Support/com.elphantroute.elephantNetwork/sing-box/sing-box-darwin' >/dev/null 2>&1 || true
/sbin/route -n delete -net 0.0.0.0/1 >/dev/null 2>&1 || true
/sbin/route -n delete -net 128.0.0.0/1 >/dev/null 2>&1 || true
/sbin/route -n delete -net 1.0.0.0/8 >/dev/null 2>&1 || true
/sbin/route -n delete -net 198.18.0.0/15 >/dev/null 2>&1 || true
/bin/rm -f "${helper}" "${plist}" "${metadata}"
