"""Configure the coursework's loopback-only Jenkins and SonarQube services."""
import base64
import json
import os
import secrets
import sys
import time
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import HTTPCookieProcessor, Request, build_opener, urlopen

JENKINS_HOME = Path(os.environ["JENKINS_HOME"])
ROOT = JENKINS_HOME.parent
EVIDENCE = ROOT / "evidence"
SONAR_URL = os.environ["SONAR_HOST_URL"]
ADMIN_FILE = JENKINS_HOME / "local-admin.pass"
JENKINS_URL = "http://127.0.0.1:18084"


def basic(value):
    return "Basic " + base64.b64encode(value.encode()).decode()


def write_password():
    if not ADMIN_FILE.exists():
        ADMIN_FILE.write_text(secrets.token_urlsafe(26))
    ADMIN_FILE.chmod(0o600)


def sonar(method, path, auth=None, **fields):
    headers = {"Authorization": auth} if auth else {}
    data = urlencode(fields).encode() if method == "POST" else None
    request = Request(f"{SONAR_URL}/{path}", method=method, headers=headers, data=data)
    with urlopen(request, timeout=8) as response:
        return response.read()


def prepare_sonar():
    for _ in range(100):
        try:
            if json.loads(sonar("GET", "api/system/status"))["status"] == "UP":
                break
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(3)
    else:
        raise SystemExit("SonarQube did not report UP. Check the lab container logs.")

    password_file = ROOT / "sonar-admin.pass"
    token_file = ROOT / "sonar-lab.token"
    if token_file.exists():
        auth = f"Bearer {token_file.read_text().strip()}"
        if json.loads(sonar("GET", "api/authentication/validate", auth))["valid"]:
            print("SonarQube is ready.")
            return
    password = password_file.read_text().strip() if password_file.exists() else ""
    auth = basic(f"admin:{password}") if password else None
    if not auth or not json.loads(sonar("GET", "api/authentication/validate", auth))["valid"]:
        password = secrets.token_urlsafe(26) + "Aa!8"
        sonar("POST", "api/users/change_password", basic("admin:admin"),
              login="admin", previousPassword="admin", password=password)
        password_file.write_text(password)
        password_file.chmod(0o600)
        auth = basic(f"admin:{password}")
    token = json.loads(sonar("POST", "api/user_tokens/generate", auth,
                            name=f"aceest-lab-{int(time.time())}", type="USER_TOKEN"))["token"]
    token_file.write_text(token)
    token_file.chmod(0o600)
    print("SonarQube is ready.")


class Jenkins:
    def __init__(self):
        self.opener = build_opener(HTTPCookieProcessor())
        password = ADMIN_FILE.read_text().strip()
        self.headers = {"Authorization": basic(f"lab-admin:{password}")}

    def get(self, path, data=None):
        request = Request(f"{JENKINS_URL}/{path}", data=data, headers=self.headers)
        with self.opener.open(request, timeout=30) as response:
            return response.read()

    def post(self, path, **fields):
        crumb = json.loads(self.get("crumbIssuer/api/json"))
        self.headers[crumb["crumbRequestField"]] = crumb["crumb"]
        return self.get(path, urlencode(fields).encode())

    def wait(self):
        for _ in range(60):
            try:
                self.get("job/Assignment1/api/json")
                print("Jenkins is ready in the Prayogshala VM.")
                return
            except (URLError, TimeoutError):
                time.sleep(3)
        raise SystemExit("Jenkins did not report ready. See evidence/jenkins-server.log.")

    def configure(self):
        script = r"""
        import jenkins.model.Jenkins
        import com.cloudbees.plugins.credentials.CredentialsScope
        import com.cloudbees.plugins.credentials.CredentialsProvider
        import com.cloudbees.plugins.credentials.domains.Domain
        import com.cloudbees.plugins.credentials.SecretBytes
        import org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl
        import org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl
        import hudson.util.Secret
        def jenkins = Jenkins.get()
        def root = jenkins.rootDir.parentFile
        def store = CredentialsProvider.lookupStores(jenkins).iterator().next()
        def domain = Domain.global()
        def configure = { credential ->
            def existing = store.getCredentials(domain).find { it.id == credential.id }
            if (existing) { store.updateCredentials(domain, existing, credential) }
            else { store.addCredentials(domain, credential) }
        }
        configure(new StringCredentialsImpl(CredentialsScope.GLOBAL,
          'aceest-sonarqube-token', 'Prayogshala SonarQube',
          Secret.fromString(new File(root, 'sonar-lab.token').text.trim())))
        configure(new FileCredentialsImpl(CredentialsScope.GLOBAL,
          'aceest-kubeconfig', 'Prayogshala Minikube cluster', 'aceest.kubeconfig',
          SecretBytes.fromBytes(new File(root, 'jenkins-flat.kubeconfig').bytes)))
        println 'Coursework credentials configured.'
        """
        response = self.post("scriptText", script=script).decode()
        if "Coursework credentials configured." not in response:
            raise SystemExit(response)
        print("Jenkins delivery credentials configured.")

    def build(self, name):
        job = f"job/{name}"

        def state():
            query = urlencode({"tree": "lastBuild[number,result,building],inQueue"})
            return json.loads(self.get(f"{job}/api/json?{query}"))

        prior = state()["lastBuild"]
        previous_number = prior["number"] if prior else 0
        self.post(f"{job}/build")
        print(f"Queued Jenkins {name}.")
        build = {}
        for _ in range(360):
            build = state().get("lastBuild") or {}
            if build.get("number", 0) > previous_number and build.get("result"):
                break
            time.sleep(3)
        else:
            raise SystemExit(f"Jenkins {name} did not finish before timeout.")
        number = build["number"]
        log = self.get(f"{job}/{number}/consoleText")
        (EVIDENCE / f"{name}-jenkins.txt").write_bytes(log)
        for artifact in ("junit.xml", "coverage.xml", "sonarqube.json", "images.txt", "deploy.log"):
            try:
                data = self.get(f"{job}/{number}/artifact/reports/{artifact}")
            except HTTPError as error:
                if error.code != 404:
                    raise
            else:
                (EVIDENCE / f"{name}-{artifact}").write_bytes(data)
        print(f"Prayogshala Jenkins {name} #{number}: {build['result']}")
        for line in log.decode(errors="replace").splitlines():
            if any(segment in line for segment in (
                "passed in ", "QUALITY GATE STATUS:", "canary:", "ab:", "mirrored request",
                "Blue-green and rolling serve", "Finished:",
            )):
                print(line)
        if build["result"] != "SUCCESS":
            raise SystemExit(f"Jenkins {name} failed. Review evidence/{name}-jenkins.txt.")


if __name__ == "__main__":
    action = sys.argv[1]
    if action == "password":
        write_password()
    elif action == "prepare-sonar":
        prepare_sonar()
    elif action == "wait-jenkins":
        Jenkins().wait()
    elif action == "configure-delivery":
        Jenkins().configure()
    elif action == "build" and len(sys.argv) == 3 and sys.argv[2] in ("Assignment1", "Assignment2"):
        Jenkins().build(sys.argv[2])
    else:
        raise SystemExit("Unknown lab action.")
