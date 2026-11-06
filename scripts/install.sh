#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build.sh "$@"
app_path="/Applications/Govee Controller.app"
if pgrep -x 'Govee Controller' >/dev/null; then
  pkill -TERM -x 'Govee Controller'
  for attempt in {1..30}; do
    pgrep -x 'Govee Controller' >/dev/null || break
    sleep 0.2
  done
  if pgrep -x 'Govee Controller' >/dev/null; then
    echo 'Govee Controller is still running. Quit it before installing.' >&2
    exit 1
  fi
fi
ditto 'build/Build/Products/Release/Govee Controller.app' "$app_path"
codesign --verify --deep --strict "$app_path"
if [ -f .env ]; then
  "$app_path/Contents/MacOS/Govee Controller" --govee-import-env "$PWD/.env"
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_path"
pluginkit -a "$app_path/Contents/PlugIns/GoveeControls.appex"
open "$app_path"
echo "Installed and launched: $app_path"
