#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/kube.sh

log=$(mktemp)
"${KUBE[@]}" --namespace aceest port-forward service/aceest-gateway :8080 >"$log" 2>&1 &
forward=$!
trap 'kill "$forward" 2>/dev/null || true; wait "$forward" 2>/dev/null || true; rm -f "$log"' EXIT
port=
for ((attempt = 0; attempt < 25; attempt++)); do
    port=$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\) ->.*/\1/p' "$log")
    if [[ -n "$port" ]]; then break; fi
    if ! kill -0 "$forward" 2>/dev/null; then break; fi
    sleep 1
done
if [[ -z "$port" ]]; then
    cat "$log" >&2
    exit 1
fi

marker="lab-$(date +%s)-$$"
python3 ci/smoke-gateway.py "http://127.0.0.1:$port" "$1" "$2" "$marker"
if [[ "$1" != "$2" ]]; then
    for ((attempt = 0; attempt < 15; attempt++)); do
        output=$(kube logs -l app=aceest,role=candidate --tail=250)
        if [[ "$output" == *"shadow_probe=$marker"* ]]; then
            echo 'The candidate access log contains the mirrored request.'
            exit 0
        fi
        sleep 1
    done
    echo 'The candidate did not log the mirrored request.' >&2
    exit 1
fi
