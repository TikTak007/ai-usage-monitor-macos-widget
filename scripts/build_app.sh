#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
configuration=${CONFIGURATION:-release}
case "$configuration" in
    release) xcode_configuration=Release ;;
    debug) xcode_configuration=Debug ;;
    *)
        echo "Unsupported CONFIGURATION: $configuration (expected release or debug)" >&2
        exit 2
        ;;
esac
app_dir="$project_dir/dist/AI Usage Monitor.app"
contents_dir="$app_dir/Contents"
executable="$project_dir/.build/$configuration/CodexUsageMonitor"
widget_dir="$contents_dir/PlugIns/CodexUsageWidget.appex"
widget_derived_data="$project_dir/.build/widget-xcode"
widget_product="$widget_derived_data/Build/Products/$xcode_configuration/CodexUsageWidget.appex"
signing_identity=${CODE_SIGN_IDENTITY:--}

cd "$project_dir"
swift build -c "$configuration"
xcodebuild \
    -project "$project_dir/CodexUsageMonitor.xcodeproj" \
    -scheme CodexUsageWidget \
    -configuration "$xcode_configuration" \
    -derivedDataPath "$widget_derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    -quiet \
    build

mkdir -p "$contents_dir/MacOS"
mkdir -p "$contents_dir/PlugIns"
cp "$executable" "$contents_dir/MacOS/CodexUsageMonitor"
cp "$project_dir/macos/Info.plist" "$contents_dir/Info.plist"
rm -rf "$widget_dir"
/usr/bin/ditto "$widget_product" "$widget_dir"

codesign \
    --force \
    --sign "$signing_identity" \
    --entitlements "$project_dir/macos/CodexUsageWidget.entitlements" \
    "$widget_dir"
codesign \
    --force \
    --sign "$signing_identity" \
    --entitlements "$project_dir/macos/CodexUsageMonitor.entitlements" \
    "$app_dir"

echo "$app_dir"
