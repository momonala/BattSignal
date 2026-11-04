#!/usr/bin/env bash
# Regenerates Resources/AppIcon.icns from Resources/AppIcon.svg.
set -euo pipefail
cd "$(dirname "$0")/.."
iconset="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift Resources/AppIcon.svg "$iconset"
iconutil -c icns "$iconset" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
