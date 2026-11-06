#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodebuild -project GoveeController.xcodeproj -scheme GoveeController \
  -configuration Release -derivedDataPath build build "$@" > build/build.log 2>&1 || {
    grep -E 'error:|warning:|BUILD FAILED' build/build.log | cut -c 1-300
    echo 'Full build output: build/build.log'
    exit 1
  }
echo "Built: $PWD/build/Build/Products/Release/Govee Controller.app"
