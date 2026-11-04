#!/usr/bin/env bash
# Builds build/BattSignal.app, replaces ~/Applications/BattSignal.app and launches it.
# Pass --build-only to skip the install and launch. SIGN_IDENTITY overrides the signing identity.
set -euo pipefail
cd "$(dirname "$0")/.."

CANDIDATE_IDENTITIES=(
    "ClaudeUsageNotch Local Signing"
)

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    available=$(security find-identity -v -p codesigning 2>/dev/null || true)
    for candidate in "${CANDIDATE_IDENTITIES[@]}"; do
        hash=$(grep -F "\"$candidate\"" <<<"$available" | grep -v "CSSMERR_" | awk '{print $2}' | head -1 || true)
        if [[ -n "$hash" ]]; then
            SIGN_IDENTITY="$hash"
            break
        fi
    done
fi
if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    echo "No signing identity in keychain, signing ad-hoc. macOS treats every rebuild as a new app." >&2
    SIGN_IDENTITY="-"
fi

swift build -c release --product BattSignal
binary="$(swift build -c release --show-bin-path)/BattSignal"

app=build/BattSignal.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/BattSignal"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --sign "$SIGN_IDENTITY" "$app"
echo "Built $app (signed with: $SIGN_IDENTITY)"

if [[ "${1:-}" != "--build-only" ]]; then
    pkill -x BattSignal || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/BattSignal.app"
    cp -R "$app" "$HOME/Applications/"
    open "$HOME/Applications/BattSignal.app"
    echo "Installed and launched ~/Applications/BattSignal.app"
fi
