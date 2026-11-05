#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Supply an installed simulator UUID; this script never uploads or signs for distribution.
: "${ZUNEYRA_SIMULATOR_ID:?Set ZUNEYRA_SIMULATOR_ID to an available iOS simulator UUID}"
output="${ZUNEYRA_VERIFY_DIRECTORY:-/tmp/zuneyra-verification}"
mkdir -p "$output"
xcodebuild -project Zuneyra.xcodeproj -scheme Zuneyra -destination 'platform=macOS' -derivedDataPath "$output/mac" OBJROOT="$output/mac/Build/Intermediates.noindex" SYMROOT="$output/mac/Build/Products" CODE_SIGN_IDENTITY=- test > "$output/mac.log" 2>&1
xcodebuild -project Zuneyra.xcodeproj -scheme Zuneyra -destination "platform=iOS Simulator,id=$ZUNEYRA_SIMULATOR_ID" -derivedDataPath "$output/ios" OBJROOT="$output/ios/Build/Intermediates.noindex" SYMROOT="$output/ios/Build/Products" CODE_SIGN_IDENTITY=- test > "$output/ios.log" 2>&1
xcodebuild -project Zuneyra.xcodeproj -scheme Zuneyra-CarPlay -destination 'generic/platform=iOS Simulator' -derivedDataPath "$output/carplay" OBJROOT="$output/carplay/Build/Intermediates.noindex" SYMROOT="$output/carplay/Build/Products" CODE_SIGNING_ALLOWED=NO build > "$output/carplay.log" 2>&1
xcodebuild -project Zuneyra.xcodeproj -scheme Zuneyra -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$output/release" OBJROOT="$output/release/Build/Intermediates.noindex" SYMROOT="$output/release/Build/Products" CODE_SIGNING_ALLOWED=NO build > "$output/release.log" 2>&1
