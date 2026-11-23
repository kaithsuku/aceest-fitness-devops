#!/usr/bin/env bash
# Source this file after enabling errexit. Require a separate cluster file.
: "${ACEEST_KUBECONFIG:?Set ACEEST_KUBECONFIG to a dedicated kubeconfig file}"
: "${ACEEST_CONTEXT:?Set ACEEST_CONTEXT to the dedicated aceest-* context}"
case "$ACEEST_CONTEXT" in
    aceest-?*) ;;
    *) echo 'The dedicated context name must start with aceest-.' >&2; exit 2 ;;
esac
if [[ ! -f "$ACEEST_KUBECONFIG" ]]; then
    echo 'The dedicated kubeconfig file does not exist.' >&2
    exit 2
fi
KUBE=(kubectl --kubeconfig "$ACEEST_KUBECONFIG" --context "$ACEEST_CONTEXT")
if [[ "$("${KUBE[@]}" config get-contexts -o name)" != "$ACEEST_CONTEXT" ]]; then
    echo 'Use a separate kubeconfig with only the assignment context.' >&2
    exit 2
fi

kube() {
    "${KUBE[@]}" --namespace aceest "$@"
}

app_image() {
    kube get "deployment/aceest-$1" -o jsonpath='{.spec.template.spec.containers[?(@.name=="app")].image}'
}

wait_app() {
    kube rollout status "deployment/aceest-$1" --timeout=120s
}

route() {
    kube patch "service/aceest-$1" --type merge -p "{\"spec\":{\"selector\":{\"role\":\"$2\"}}}"
}
