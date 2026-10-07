#!/bin/bash
# Generates the Xcode project from project.yml and runs the app's unit tests.
# Extra arguments are passed to xcodebuild (e.g. -only-testing:SSHConfigManagerTests/LocalizationTests).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --spec project.yml --quiet
xcodebuild test \
  -project SSHConfigManager.xcodeproj \
  -scheme SSHConfigManager \
  -destination 'platform=macOS,arch=arm64' \
  -quiet "$@"
