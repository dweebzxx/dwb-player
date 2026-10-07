#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="${0:A:h}/.."
PROJECT_PATH="$ROOT_DIR/dwb/dwb.xcodeproj"
SCHEME="${DWB_TEST_SCHEME:-dwbTests}"
CONFIGURATION="${DWB_TEST_CONFIGURATION:-Debug}"
DESTINATION="${DWB_TEST_DESTINATION:-platform=macOS}"
CLANG_CACHE_PATH="${DWB_CLANG_MODULE_CACHE_PATH:-$ROOT_DIR/.tmp/clang-module-cache}"
SWIFT_CACHE_PATH="${DWB_SWIFT_MODULE_CACHE_PATH:-$ROOT_DIR/.tmp/swift-module-cache}"
SWIFTPM_CACHE_PATH="${DWB_PACKAGE_CACHE_PATH:-$ROOT_DIR/.tmp/swiftpm-cache}"

derived_data_args=()
if [[ -n "${DWB_TEST_DERIVED_DATA_PATH:-}" ]]; then
    derived_data_args=(-derivedDataPath "$DWB_TEST_DERIVED_DATA_PATH")
    mkdir -p "$DWB_TEST_DERIVED_DATA_PATH"
fi

mkdir -p "$CLANG_CACHE_PATH" "$SWIFT_CACHE_PATH" "$SWIFTPM_CACHE_PATH"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    "${derived_data_args[@]}" \
    -packageCachePath "$SWIFTPM_CACHE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    CLANG_MODULE_CACHE_PATH="$CLANG_CACHE_PATH" \
    SWIFT_MODULE_CACHE_PATH="$SWIFT_CACHE_PATH" \
    -skipPackageUpdates \
    -onlyUsePackageVersionsFromResolvedFile \
    test
