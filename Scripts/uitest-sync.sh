#!/bin/bash
# Runs the UI test of the folder sync against a local HTTP server.
#
# The UI test runner may not bind a port, so the server runs out here, on a
# high port of 127.0.0.1. The port reaches the test through a TEST_RUNNER_
# variable, which xcodebuild copies into the runner's environment.
#
# Usage: ./Scripts/uitest-sync.sh
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=${TMPDIR:-/tmp}
dir=$(mktemp -d "${tmp%/}/shellyard-uitest-sync.XXXXXX")
server_pid=""
trap '{ [ -n "$server_pid" ] && kill "$server_pid"; rm -rf "$dir"; } 2>/dev/null || true' EXIT

swiftc -O -o "$dir/server" Scripts/sync-test-server.swift
port=$(( (RANDOM % 30000) + 22000 ))
"$dir/server" "$port" > "$dir/server.log" 2>&1 &
server_pid=$!
for _ in $(seq 1 100); do
    nc -z 127.0.0.1 "$port" 2>/dev/null && break
    sleep 0.05
done

TEST_RUNNER_SHELLYARD_TEST_SYNC_PORT=$port \
xcodebuild -project Shellyard.xcodeproj -scheme Shellyard \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build \
    -only-testing:ShellyardUITests/FolderSyncTests test
