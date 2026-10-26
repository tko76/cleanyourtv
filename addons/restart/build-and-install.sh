#!/usr/bin/env bash
# Build Restart TV, install it on the TV and enable its accessibility service (only shows the system
# power dialog, reads nothing). One press on the tile shows Restart / Cancel.
#
# Usage: TV_HOST=192.168.1.50 addons/restart/build-and-install.sh
#        TV_HOST=192.168.1.50 addons/restart/build-and-install.sh --uninstall
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOLS="$HERE/../../tools"
: "${TV_HOST:?set TV_HOST to the TV IP address, e.g. TV_HOST=192.168.1.50 $0}"
PY="$TOOLS/venv/bin/python"
[ -x "$PY" ] || PY="$TOOLS/venv/Scripts/python.exe"
[ -x "$PY" ] || { echo "run: python3 -m venv tools/venv && tools/venv/bin/pip install -r tools/requirements.txt" >&2; exit 1; }
export MSYS_NO_PATHCONV=1
PKG=io.github.tko76.restarttv
SVC=$PKG/$PKG.PowerService
tv() { "$PY" -I "$TOOLS/tv.py" "$@"; }

if [ "${1:-}" = --uninstall ]; then
    tv "s=\$(settings get secure enabled_accessibility_services); s=\$(echo \":\$s:\" | sed 's#:$SVC:#:#; s#^:##; s#:\$##'); if [ -z \"\$s\" ]; then settings delete secure enabled_accessibility_services; else settings put secure enabled_accessibility_services \$s; fi; pm uninstall $PKG"
    exit 0
fi

(cd "$HERE" && ./gradlew assembleRelease -q) || { echo "build failed (JDK 17 and Android SDK 34 needed; see launcher/README)" >&2; exit 1; }
"$PY" -I "$TOOLS/b64push.py" "$HERE/app/build/outputs/apk/release/app-release.apk" /data/local/tmp/restart.apk >/dev/null
tv "pm install -r /data/local/tmp/restart.apk; rm -f /data/local/tmp/restart.apk"
# Add PowerService to the enabled accessibility services list without disturbing others.
tv "s=\$(settings get secure enabled_accessibility_services); case :\$s: in *:$SVC:*) ;; *) if [ -z \$s ] || [ \$s = null ]; then s=$SVC; else s=\$s:$SVC; fi; settings put secure enabled_accessibility_services \$s;; esac; settings put secure accessibility_enabled 1"
# Allow auto-start so the service binds on TCL firmware that withholds it otherwise.
tv "appops set $PKG AUTO_START allow 2>/dev/null; appops set $PKG APP_AUTO_START allow 2>/dev/null; appops write-settings 2>/dev/null; true" >/dev/null
echo "Installed. The Restart tile on the launcher opens the system power dialog."
