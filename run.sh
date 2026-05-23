#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Build (release for smooth scroll), then launch.
swift build -c release
exec ./.build/release/SparklePrompt
