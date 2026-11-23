# ACEest Fitness & Gym

This repository contains two Flask releases from one Git history. Assignment 1 is the continuous integration baseline, tagged `v1.0.0` and available on the `assignment-1` branch. Assignment 2 adds a release pipeline and a calorie estimate based on the multipliers in the supplied `Aceestver-1.1.py`. The second Flask release is tagged `v1.1.0`.

## Run and test the app

Use Python 3.12.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m pytest -q
python -m flask --app app run
```

Open <http://127.0.0.1:5000>. The three original fitness programs are available at `/api/programs`. Version 1.1.0 adds `/api/programs/fl/estimate?weight_kg=70`. The `/healthz` and `/version` routes are used by deployment checks.

```sh
docker build --target test -t aceest:test .
bash ci/test-image.sh aceest:test
docker build --target runtime -t aceest:1.1.0 .
docker run --rm -p 127.0.0.1:8000:8000 aceest:1.1.0
```

## Configure the Assignment 2 Jenkins job

1. Create a **Pipeline** job from SCM. Select Git, enter this repository's HTTPS URL, and select `*/main` and `Jenkinsfile`. Enable tag fetch and use full checkout for this job.
2. Use a trusted Unix agent with label `docker`. Install Git, Bash, Docker, Python 3, SonarScanner CLI, and a compatible `kubectl`. In Jenkins, install Pipeline, Git, Credentials Binding, JUnit, and Timestamper.
3. In the agent's node properties, set the environment variables below. Node properties give both manual and polled builds the same settings.
4. Add Jenkins credentials `aceest-sonarqube-token` (Secret text with Analyze and Browse access), `aceest-kubeconfig` (Secret file for the dedicated cluster), and `aceest-dockerhub` (Username with password, using a write-enabled Docker Hub access token). Use a public Docker Hub image repository or configure registry pull credentials on the cluster.
5. Select **Build Now** once. Jenkins polls the branch about every five minutes after this first run. The pipeline cleans the workspace, checks syntax and lint, runs container-based Pytest, and checks SonarQube. It builds and distributes the runtime image only after the gate passes. The release stage records the image tags. The deployment stage checks both releases, configures the five routes, and verifies their behavior. Find JUnit, coverage, the SonarQube report, the image references, and the deploy log in the build artifacts.

| Jenkins agent variable | Value |
| --- | --- |
| `SONAR_HOST_URL` | URL of your SonarQube Server or Community Build instance |
| `ACEEST_CONTEXT` | The only context in the dedicated kubeconfig. Use a name beginning with `aceest-`. |
| `RELEASE_TARGET` | `docker-hub` for registry publication, or `minikube` for an isolated local rehearsal |
| `DOCKERHUB_REPO` | Your Docker Hub repository in `namespace/repository` form |
| `MINIKUBE_HOME` | Dedicated Minikube state directory when `RELEASE_TARGET=minikube` |

Create the `aceest-fitness` project in SonarQube and use a token with permission to submit an analysis and read its results. The scanner waits for the quality gate. A failed scan or gate stops the pipeline before image distribution.

Docker Hub tags use the application version and 12 Git SHA characters. Jenkins takes the baseline from Git tag `v1.0.0` and takes the candidate from the checked-out commit. The deployment retains the selected baseline. Use a fresh dedicated lab if you change the baseline image reference. Stop other deploy jobs for the same namespace before running this job.

## Run a separate local Minikube lab

Use Docker and Minikube. The commands below set the kubeconfig only for this shell. Keep the lab credentials out of Git.

```sh
mkdir -p .lab
export ACEEST_KUBECONFIG="$PWD/.lab/aceest.kubeconfig"
export ACEEST_CONTEXT=aceest-coursework
export MINIKUBE_HOME="$PWD/.lab"
export KUBECONFIG="$ACEEST_KUBECONFIG"
minikube start --profile "$ACEEST_CONTEXT" --driver=docker
```

Build the baseline from its tag and the candidate from the current checkout.

```sh
baseline=$(mktemp -d)
git archive v1.0.0 | tar -x -C "$baseline"
docker build --target runtime -t aceest-lab:1.0.0 "$baseline"
docker build --target runtime -t aceest-lab:1.1.0 .
minikube --profile "$ACEEST_CONTEXT" image load aceest-lab:1.0.0
minikube --profile "$ACEEST_CONTEXT" image load aceest-lab:1.1.0
bash ci/deploy.sh aceest-lab:1.0.0 1.0.0 aceest-lab:1.1.0 1.1.0
```

For a demo, keep this port-forward running in a terminal.

```sh
kubectl --kubeconfig "$ACEEST_KUBECONFIG" --context "$ACEEST_CONTEXT" \
  --namespace aceest port-forward service/aceest-gateway 18080:8080
```

Open <http://127.0.0.1:18080>. The gateway redirects to the rolling route. Each path below also serves the Flask site when you remove `version` from the URL.

| Strategy | Check | Expected after deployment |
| --- | --- | --- |
| Blue-green | `/blue-green/version` | The service switches to the ready 1.1.0 group. |
| Canary | `/canary/version` | 10% of hashed request IDs go to 1.1.0. The rest go to 1.0.0. Use different `X-Demo-Request` values. |
| Shadow | `/shadow/version` | The client sees 1.0.0. The gateway sends a background copy to 1.1.0. |
| A/B | `/ab/version` | The gateway assigns each `X-Demo-User` to a fixed 50/50 cohort. |
| Rolling | `/rolling/version` | Kubernetes replaces the pods one at a time. The route ends on 1.1.0. |

```sh
bash ci/smoke-gateway.sh 1.0.0 1.1.0
bash ci/rollback.sh
bash ci/smoke-gateway.sh 1.0.0 1.0.0
```

The smoke test checks 160 canary request IDs and 160 A/B user IDs. It also checks that the candidate access log contains the shadow request marker. The rollback returns all five routes to the baseline. On a failed deployment, the deploy script restores the stable routing selectors and the rolling image from the start of that run.
