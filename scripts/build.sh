#!/bin/zsh
set -euo pipefail
DUOBAR_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
DUOBAR_BUILD="$DUOBAR_ROOT/build"
mkdir -p "$DUOBAR_BUILD"
DUOBAR_STAGE=$(mktemp -d "$DUOBAR_BUILD/app-stage.XXXXXX")
trap 'rm -rf "$DUOBAR_STAGE"' EXIT
DUOBAR_APP="$DUOBAR_STAGE/DuoBar.app"
DUOBAR_SDK="$(xcrun --show-sdk-path)"
mkdir -p "$DUOBAR_APP/Contents/MacOS" "$DUOBAR_APP/Contents/Resources" "$DUOBAR_BUILD/module-cache" "$DUOBAR_BUILD/bin"
for DUOBAR_ARCH in arm64 x86_64; do
    xcrun swiftc -O -whole-module-optimization -swift-version 5 \
        -target "$DUOBAR_ARCH-apple-macosx13.0" -sdk "$DUOBAR_SDK" \
        -module-cache-path "$DUOBAR_BUILD/module-cache" \
        -framework AppKit -framework CoreWLAN -framework CoreAudio -framework IOKit \
        -framework Intents -framework Network -framework SystemConfiguration -framework ServiceManagement -framework CoreLocation -framework Security \
        "$DUOBAR_ROOT"/Sources/*.swift -o "$DUOBAR_BUILD/bin/DuoBar-$DUOBAR_ARCH"
done
xcrun lipo -create "$DUOBAR_BUILD/bin/DuoBar-arm64" "$DUOBAR_BUILD/bin/DuoBar-x86_64" -output "$DUOBAR_APP/Contents/MacOS/DuoBar"
cp -X "$DUOBAR_ROOT/Resources/Info.plist" "$DUOBAR_APP/Contents/Info.plist"
cp -X "$DUOBAR_ROOT/Resources/AppIcon.icns" "$DUOBAR_APP/Contents/Resources/AppIcon.icns"
/usr/bin/plutil -lint "$DUOBAR_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$DUOBAR_APP"
"$DUOBAR_ROOT/scripts/verify-app.sh" "$DUOBAR_APP"
# Replace only the generated app, after the fresh bundle has passed validation.
rm -rf "$DUOBAR_BUILD/DuoBar.app"
mv "$DUOBAR_APP" "$DUOBAR_BUILD/DuoBar.app"
printf 'Built: %s\n' "$DUOBAR_BUILD/DuoBar.app"
