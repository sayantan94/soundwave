#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build -c release
task_bin_dir="$(swift build -c release --show-bin-path)"
task_app="$PWD/dist/SoundWave.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
cp "$task_bin_dir/SoundWave" "$task_app/Contents/MacOS/SoundWave"
cp Resources/Info.plist "$task_app/Contents/Info.plist"
swift scripts/make-icon.swift "$PWD/dist"
iconutil -c icns "$PWD/dist/AppIcon.iconset" -o "$task_app/Contents/Resources/AppIcon.icns"
# Prefer an existing local development identity so macOS permissions survive rebuilds.
# Fall back to ad-hoc signing on Macs without a development certificate.
task_identity="${SOUNDWAVE_SIGNING_IDENTITY:-}"
if [[ -z "$task_identity" ]]; then
    task_identity="$(security find-identity -v -p codesigning | awk '/Apple Development:/{print $2; exit}')"
fi
codesign --force --sign "${task_identity:--}" --identifier local.soundwave.mac "$task_app"
codesign --verify --strict "$task_app"
echo "Built: $task_app"
