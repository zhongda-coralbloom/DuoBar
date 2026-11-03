#!/bin/zsh
set -euo pipefail
DUOBAR_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
mkdir -p "$DUOBAR_ROOT/build/tests" "$DUOBAR_ROOT/build/module-cache"
xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "$DUOBAR_ROOT/build/module-cache" \
    "$DUOBAR_ROOT/Sources/StatusModel.swift" "$DUOBAR_ROOT/Sources/DotPreferences.swift" "$DUOBAR_ROOT/Sources/TunnelRoutes.swift" "$DUOBAR_ROOT/Tests/StatusTests.swift" \
    -o "$DUOBAR_ROOT/build/tests/StatusTests"
"$DUOBAR_ROOT/build/tests/StatusTests"

xcrun swiftc -O -swift-version 5 -module-cache-path "$DUOBAR_ROOT/build/module-cache" \
    "$DUOBAR_ROOT/Sources/StatusModel.swift" "$DUOBAR_ROOT/Sources/DotPreferences.swift" \
    "$DUOBAR_ROOT/Sources/DuoIcon.swift" "$DUOBAR_ROOT/Sources/IconMotion.swift" "$DUOBAR_ROOT/Sources/StatusIconView.swift" \
    "$DUOBAR_ROOT/Tests/IconTests.swift" -o "$DUOBAR_ROOT/build/tests/IconTests"
"$DUOBAR_ROOT/build/tests/IconTests"

xcrun swiftc -O -swift-version 5 -module-cache-path "$DUOBAR_ROOT/build/module-cache" \
    -framework CoreWLAN -framework CoreLocation -framework Security \
    "$DUOBAR_ROOT/Sources/StatusModel.swift" "$DUOBAR_ROOT/Sources/DotPreferences.swift" \
    "$DUOBAR_ROOT/Sources/DuoIcon.swift" "$DUOBAR_ROOT/Sources/IconMotion.swift" \
    "$DUOBAR_ROOT/Sources/SystemSettings.swift" "$DUOBAR_ROOT/Sources/WiFiController.swift" \
    "$DUOBAR_ROOT/Sources/StatusPanel.swift" \
    "$DUOBAR_ROOT/Tests/PanelTests.swift" -o "$DUOBAR_ROOT/build/tests/PanelTests"
"$DUOBAR_ROOT/build/tests/PanelTests"
