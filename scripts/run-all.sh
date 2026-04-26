#!/usr/bin/env bash
# Launches the server, the bots, and the Godot client.
# Usage: bash scripts/run-all.sh [--release]
#
# Override the Godot binary with the GODOT env var (default: "godot").

set -euo pipefail

RepoRoot="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ServerDir="$RepoRoot/Server"
ClientDir="$RepoRoot/Client"
GODOT_BIN="${GODOT:-godot}"

CARGO_PROFILE_FLAG=""
if [[ "${1:-}" == "--release" ]]; then
    CARGO_PROFILE_FLAG="--release"
fi

pids=()

cleanup() {
    echo
    echo "[run-all] Stopping child processes…"
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[run-all] Starting server…"
( cd "$ServerDir" && cargo run $CARGO_PROFILE_FLAG --bin server ) &
pids+=($!)

echo "[run-all] Waiting for server on ws://localhost:8080…"
for _ in $(seq 1 120); do
    if (echo > /dev/tcp/localhost/8080) >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

echo "[run-all] Starting bots…"
( cd "$ServerDir" && cargo run $CARGO_PROFILE_FLAG --bin bots ) &
pids+=($!)

echo "[run-all] Starting Godot client ($GODOT_BIN)…"
( cd "$ClientDir" && "$GODOT_BIN" --path "$ClientDir" ) &
pids+=($!)

echo "[run-all] All processes launched. Ctrl+C to stop."
wait
