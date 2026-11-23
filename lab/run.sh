#!/usr/bin/env bash
# Run the coursework from the Introduction to DevOps Prayogshala VM.
set -euo pipefail
umask 022

helper=$(cd "$(dirname "$0")" && pwd)
root="$HOME/workspace/aceest-prayogshala"
mkdir -p "$root"/{bin,evidence,jenkins/plugins,jenkins/init.groovy.d,minikube}
chmod 700 "$root" "$root/jenkins"
exec > >(tee -a "$root/evidence/lab-run.log") 2>&1
cd "$root"
export PATH="$root/bin:$PATH"
export JENKINS_HOME="$root/jenkins"
export MINIKUBE_HOME="$root/minikube"
export SONAR_USER_HOME="$root/sonar-cache"
export SONAR_HOST_URL=http://127.0.0.1:19000
export ACEEST_CONTEXT=aceest-prayogshala
export KUBECONFIG="$root/aceest-prayogshala.kubeconfig"

repository=https://github.com/kaithsuku/aceest-fitness-devops.git
case "$(uname -m)" in
    x86_64) arch=amd64; java_arch=x64 ;;
    aarch64) arch=arm64; java_arch=aarch64 ;;
    *) echo 'Unsupported lab architecture.' >&2; exit 2 ;;
esac
download() {
    if [[ ! -s "$2" ]]; then
        curl --fail --silent --show-error --location --retry 2 --max-time 240 "$1" -o "$2.part"
        mv "$2.part" "$2"
    fi
}
clone() {
    if [[ ! -d "$2/.git" ]]; then git clone --branch "$1" "$repository" "$2"; fi
}

echo "Prayogshala SEZG514 verification at $(date -Is)"
docker version --format 'Docker server {{.Server.Version}}'
clone assignment-1 assignment-1
clone main assignment-2
git -C assignment-2 merge-base --is-ancestor origin/assignment-1 HEAD

# The server binds only to the lab desktop's loopback address.
java_bin=$(command -v java)
java_major=$("$java_bin" -version 2>&1 | awk -F'[".]' 'NR == 1 {print $2}')
if [[ ! "$java_major" =~ ^[0-9]+$ ]] || (( java_major < 21 )); then
    download "https://api.adoptium.net/v3/binary/latest/21/ga/linux/$java_arch/jre/hotspot/normal/eclipse" "$root/java21.tar.gz"
    mkdir -p "$root/java21"
    tar -xzf "$root/java21.tar.gz" -C "$root/java21" --strip-components=1
    java_bin="$root/java21/bin/java"
fi
export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$java_bin")")")"
export PATH="$JAVA_HOME/bin:$PATH"
download https://get.jenkins.io/war-stable/2.580.2/jenkins.war "$root/jenkins.war"
if ! compgen -G "$JENKINS_HOME/plugins/workflow-aggregator.*" > /dev/null; then
    download https://github.com/jenkinsci/plugin-installation-manager-tool/releases/download/2.16.0/jenkins-plugin-manager-2.16.0.jar "$root/plugin-manager.jar"
    "$java_bin" -jar "$root/plugin-manager.jar" --war "$root/jenkins.war" \
        --plugin-download-directory "$JENKINS_HOME/plugins" \
        --plugins workflow-aggregator git junit timestamper credentials-binding
fi
download https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-8.3.1.16491.zip "$root/sonar-scanner.zip"
if [[ ! -d "$root/sonar-scanner-8.3.1.16491" ]]; then
    python3 -m zipfile -e "$root/sonar-scanner.zip" "$root"
fi
ln -sfn "$root/sonar-scanner-8.3.1.16491/bin/sonar-scanner" "$root/bin/sonar-scanner"
chmod +x "$root/bin/sonar-scanner"
cp "$helper/jenkins-init.groovy" "$JENKINS_HOME/init.groovy.d/01-prayogshala.groovy"
python3 "$helper/services.py" password
if ! curl -fsS -o /dev/null --max-time 4 http://127.0.0.1:18084/login; then
    nohup "$java_bin" -Xmx768m -Djenkins.install.runSetupWizard=false -jar "$root/jenkins.war" \
        --httpListenAddress=127.0.0.1 --httpPort=18084 > "$root/evidence/jenkins-server.log" 2>&1 < /dev/null &
fi
python3 "$helper/services.py" wait-jenkins
python3 "$helper/services.py" build Assignment1
echo 'Assignment 1 succeeded. Preparing the Assignment 2 services.'

if ! docker container inspect aceest-prayogshala-sonar >/dev/null 2>&1; then
    docker run -d --name aceest-prayogshala-sonar --label aceest.coursework=prayogshala \
      -p 127.0.0.1:19000:9000 -e SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true \
      -v aceest-prayogshala-sonar-data:/opt/sonarqube/data sonarqube:community >/dev/null
else
    docker start aceest-prayogshala-sonar >/dev/null
fi
python3 "$helper/services.py" prepare-sonar

if ! command -v minikube >/dev/null; then
    download "https://storage.googleapis.com/minikube/releases/v1.39.0/minikube-linux-$arch" "$root/bin/minikube"
    chmod 755 "$root/bin/minikube"
fi
minikube start --profile "$ACEEST_CONTEXT" --driver=docker --cpus=2 --memory=2500
# Use the client bundled with this Minikube version.
minikube --profile "$ACEEST_CONTEXT" kubectl -- version
cat > "$root/bin/kubectl" <<'WRAPPER'
#!/usr/bin/env bash
exec minikube --profile aceest-prayogshala kubectl -- "$@"
WRAPPER
chmod 755 "$root/bin/kubectl"
(
    umask 077
    kubectl --kubeconfig "$KUBECONFIG" --context "$ACEEST_CONTEXT" config view --raw --flatten --minify \
        > "$root/jenkins-flat.kubeconfig"
)

python3 "$helper/services.py" configure-delivery
python3 "$helper/services.py" build Assignment2
echo 'Verifying explicit rollback to the Assignment 1 release.'
export ACEEST_KUBECONFIG="$KUBECONFIG"
candidate_tag="1.1.0-$(git -C assignment-2 rev-parse --short=12 HEAD)"
(
    cd assignment-2
    bash ci/rollback.sh
    bash ci/smoke-gateway.sh 1.0.0 1.0.0
    bash ci/deploy.sh aceest-lab:1.0.0 1.0.0 "aceest-lab:$candidate_tag" 1.1.0
) 2>&1 | tee "$root/evidence/rollback-and-restore.log"

if ! curl -fsS -o /dev/null --max-time 3 http://127.0.0.1:18080/rolling/version; then
    nohup kubectl --kubeconfig "$KUBECONFIG" --context "$ACEEST_CONTEXT" -n aceest \
      port-forward service/aceest-gateway 18080:8080 > "$root/evidence/gateway.log" 2>&1 < /dev/null &
fi
curl --fail --silent --show-error --retry 8 --retry-connrefused --max-time 4 http://127.0.0.1:18080/rolling/version
echo 'Both Prayogshala runs succeeded. Evidence is in ~/workspace/aceest-prayogshala/evidence.'
