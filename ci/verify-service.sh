#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/kube.sh

log=$(mktemp)
# An omitted local port asks kubectl for a free loopback port.
"${KUBE[@]}" --namespace aceest port-forward "service/aceest-$1" :8000 >"$log" 2>&1 &
forward=$!
trap 'kill "$forward" 2>/dev/null || true; rm -f "$log"' EXIT
for ((attempt = 0; attempt < 25; attempt++)); do
    port=$(sed -n 's/.*127\.0\.0\.1:\([0-9][0-9]*\) ->.*/\1/p' "$log")
    if [[ -n "$port" ]]; then
        python3 ci/check-service.py "http://127.0.0.1:$port" "$2"
        exit
    fi
    if ! kill -0 "$forward" 2>/dev/null; then break; fi
    sleep 1
done
cat "$log" >&2
exit 1
