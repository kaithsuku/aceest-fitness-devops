#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/kube.sh

stable_image=$(app_image stable)
route blue-green stable
route experiment stable
kube set image deployment/aceest-rolling "app=$stable_image"
wait_app rolling
