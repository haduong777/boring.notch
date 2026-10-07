#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BINARY="$(mktemp /private/tmp/notch-codex-tests.XXXXXX)"
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc "$PROJECT_ROOT/BoringNotchXPCHelper/CodexUsageSnapshot.swift" \
  "$PROJECT_ROOT/BoringNotchXPCHelper/CodexUsageReader.swift" \
  "$PROJECT_ROOT/Tests/CodexUsage/main.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
