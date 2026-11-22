#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
skill_dir="$(cd "$script_dir/.." && pwd)"
runtime_dir="$skill_dir/.runtime"
app_dir="$runtime_dir/ApplePhotosBridge.app"
binary="$app_dir/Contents/MacOS/ApplePhotosBridge"
source_file="$script_dir/ApplePhotosBridge.swift"
plist_file="$script_dir/Info.plist"

needs_build=0
if [[ ! -x "$binary" ]]; then
  needs_build=1
elif [[ "$source_file" -nt "$binary" || "$plist_file" -nt "$binary" ]]; then
  needs_build=1
fi

if [[ "$needs_build" -eq 1 ]]; then
  mkdir -p "$app_dir/Contents/MacOS"
  mkdir -p "$app_dir/Contents/Resources"
  xcrun swiftc "$source_file" -o "$binary" -framework AppKit -framework Photos
  cp "$plist_file" "$app_dir/Contents/Info.plist"
  plutil -lint "$app_dir/Contents/Info.plist" >/dev/null
  codesign --force --sign - "$app_dir" >/dev/null
fi

printf '{"type":"install","status":"ok","built":%s,"app":"%s"}\n' "$needs_build" "$app_dir"
