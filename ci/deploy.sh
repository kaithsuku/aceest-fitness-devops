#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source ci/kube.sh

if [[ "$#" != 4 ]]; then
    echo 'Usage: ci/deploy.sh STABLE_IMAGE STABLE_VERSION CANDIDATE_IMAGE CANDIDATE_VERSION' >&2
    exit 2
fi
stable_image=$1
stable_version=$2
candidate_image=$3
candidate_version=$4
for image in "$stable_image" "$candidate_image"; do
    if [[ ! "$image" =~ ^[a-zA-Z0-9][a-zA-Z0-9./_:@-]+$ ]]; then
        echo 'Invalid container image name.' >&2
        exit 2
    fi
done

apply_app() {
    sed -e "s|__ROLE__|$1|g" -e "s|__IMAGE__|$2|g" -e "s|__REPLICAS__|$3|g" \
        k8s/app-deployment.yaml | kube apply -f -
}

# Keep the designated stable image fixed on repeat deployments.
"${KUBE[@]}" apply -f k8s/namespace.yaml
previous_stable=$(app_image stable 2>/dev/null || true)
if [[ -n "$previous_stable" && "$previous_stable" != "$stable_image" ]]; then
    echo "Stable image differs from the installed baseline: $previous_stable" >&2
    exit 2
fi
apply_app stable "$stable_image" 2
wait_app stable
kube apply -f k8s/services.yaml
bash ci/verify-service.sh stable "$stable_version"
# Explicitly reset selectors. kubectl apply alone can retain a manual patch.
route blue-green stable
route experiment stable

previous_rolling=$(app_image rolling 2>/dev/null || true)
rollback_on_error() {
    status=$?
    trap - EXIT
    if [[ "$status" != 0 ]]; then
        echo 'Deployment failed. Restoring the stable routes and prior rolling image.' >&2
        set +e
        restore_status=0
        route blue-green stable || restore_status=1
        route experiment stable || restore_status=1
        kube set image deployment/aceest-rolling "app=$previous_rolling" || restore_status=1
        wait_app rolling || restore_status=1
        if [[ "$restore_status" != 0 ]]; then
            echo 'Automatic rollback requires attention. Review the kubectl output.' >&2
        fi
    fi
    exit "$status"
}

if [[ -z "$previous_rolling" ]]; then
    apply_app rolling "$stable_image" 2
    wait_app rolling
    bash ci/verify-service.sh rolling "$stable_version"
    previous_rolling=$stable_image
fi
trap rollback_on_error EXIT

apply_app candidate "$candidate_image" 2
wait_app candidate
bash ci/verify-service.sh candidate "$candidate_version"

config_hash=$(python3 -c 'import hashlib; print(hashlib.sha256(open("k8s/nginx.conf", "rb").read()).hexdigest()[:12])')
kube create configmap "aceest-routing-$config_hash" --from-file=default.conf=k8s/nginx.conf \
    --dry-run=client -o yaml | kube apply -f -
sed "s/__CONFIG_HASH__/$config_hash/g" k8s/gateway.yaml | kube apply -f -
kube rollout status deployment/aceest-gateway --timeout=120s

# Canary, A/B and shadow share this selector. Blue-green has its own switch.
route experiment candidate
route blue-green candidate
apply_app rolling "$candidate_image" 2
wait_app rolling
bash ci/verify-service.sh rolling "$candidate_version"
bash ci/smoke-gateway.sh "$stable_version" "$candidate_version"
trap - EXIT
