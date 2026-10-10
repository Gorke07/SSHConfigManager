#!/bin/bash
# Checks the String Catalog (scripts/check-localization.py), generates the Xcode project from project.yml and runs the app's unit tests.
# Extra arguments are passed to xcodebuild (e.g. -only-testing:SSHConfigManagerTests/LocalizationTests).
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest scripts/test_check_localization.py
python3 scripts/check-localization.py
xcodegen generate --spec project.yml --quiet
xcodebuild test \
  -project SSHConfigManager.xcodeproj \
  -scheme SSHConfigManager \
  -destination "platform=macOS,arch=$(uname -m)" \
  -quiet "$@"
