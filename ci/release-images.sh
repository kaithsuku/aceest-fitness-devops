#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_TARGET:?Set RELEASE_TARGET}"
: "${CANDIDATE_TAG:?Set CANDIDATE_TAG}"
: "${ACEEST_KUBECONFIG:?Set ACEEST_KUBECONFIG}"
: "${ACEEST_CONTEXT:?Set ACEEST_CONTEXT}"
source ci/kube.sh

baseline=$(mktemp -d)
registry_config=
cleanup() {
    rm -rf "$baseline"
    if [[ -n "$registry_config" ]]; then rm -rf "$registry_config"; fi
}
trap cleanup EXIT

git archive v1.0.0 | tar -x -C "$baseline"
if [[ "$RELEASE_TARGET" == docker-hub ]]; then
    if [[ ! "${DOCKERHUB_REPO:-}" =~ ^[a-z0-9][a-z0-9_-]*/[a-z0-9][a-z0-9._-]*$ ]]; then
        echo 'Set DOCKERHUB_REPO to your Docker Hub namespace and repository.' >&2
        exit 2
    fi
    repository="docker.io/$DOCKERHUB_REPO"
    registry_config=$(mktemp -d)
    # Keep the selected Unix daemon when switching Docker to a temporary credential file.
    docker_endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
    if [[ "$docker_endpoint" != unix://* ]]; then
        echo 'Use a dedicated Jenkins agent with a Unix Docker endpoint.' >&2
        exit 2
    fi
    unset DOCKER_CONTEXT
    export DOCKER_HOST="$docker_endpoint" DOCKER_CONFIG="$registry_config"
    printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$DOCKERHUB_USER" --password-stdin docker.io
    stable_tag="1.0.0-$(git rev-parse --short=12 v1.0.0^{commit})"
else
    if [[ "$RELEASE_TARGET" != minikube ]]; then
        echo 'Use docker-hub or minikube as RELEASE_TARGET.' >&2
        exit 2
    fi
    repository=aceest-lab
    stable_tag=1.0.0
fi

stable_image="$repository:$stable_tag"
candidate_image="$repository:$CANDIDATE_TAG"

docker build --target runtime -t "$candidate_image" .
if [[ "$RELEASE_TARGET" == docker-hub ]]; then
    if ! docker pull "$stable_image"; then
        docker build --target runtime -t "$stable_image" "$baseline"
        docker push "$stable_image"
    fi
    docker push "$candidate_image"
else
    : "${MINIKUBE_HOME:?Set MINIKUBE_HOME to the dedicated Minikube state directory}"
    docker build --target runtime -t "$stable_image" "$baseline"
    KUBECONFIG="$ACEEST_KUBECONFIG" minikube --profile "$ACEEST_CONTEXT" image load "$stable_image"
    KUBECONFIG="$ACEEST_KUBECONFIG" minikube --profile "$ACEEST_CONTEXT" image load "$candidate_image"
fi

mkdir -p reports
printf 'stable=%s\ncandidate=%s\n' "$stable_image" "$candidate_image" > reports/images.txt
