#!/usr/bin/env bash
set -euo pipefail

repo_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_directory"
build_directory="${1:-build/ios}"
ipa_path="${2:-dist/Harmony.ipa}"
if [[ "$(basename "$ipa_path")" != Harmony.ipa ]]; then
    echo "The IPA filename must be Harmony.ipa." >&2
    exit 1
fi
mkdir -p "$build_directory" "$(dirname "$ipa_path")"
build_directory="$(cd "$build_directory" && pwd)"

swift Scripts/GenerateXcodeProject.swift
xcodebuild -project Harmony.xcodeproj -scheme Harmony -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath "$build_directory/DerivedData" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build

package_directory="$(mktemp -d "$build_directory/package.XXXXXX")"
mkdir -p "$package_directory/Payload"
ditto "$build_directory/DerivedData/Build/Products/Release-iphoneos/Harmony.app" \
    "$package_directory/Payload/Harmony.app"
ditto -c -k --keepParent "$package_directory/Payload" "$package_directory/Harmony.ipa"
mv "$package_directory/Harmony.ipa" "$ipa_path"
python3 Scripts/VerifyIPA.py "$ipa_path"
