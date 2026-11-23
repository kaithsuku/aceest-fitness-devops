# ACEest Fitness & Gym

## Assignment 1

ACEest is a Flask web app for the fitness catalog in the supplied `Aceestver-1.0.py` desktop program. It keeps the three original programs and displays each workout and nutrition plan in a browser and through a JSON API. `ACEest_Fitness.py` holds the program data. `app.py` contains the Flask routes.

## Run locally

Use Python 3.12 and run these commands from the repository root.

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements-dev.txt
python -m flask --app app run
```

Open <http://127.0.0.1:5000>. The API lists the programs at `/api/programs`. To see one program, use `/api/programs/fl`, `/api/programs/mg`, or `/api/programs/bg`. Use `/healthz` for service health and `/version` for the release number.

On Windows PowerShell, use `py -3.12 -m venv .venv` and `.\.venv\Scripts\Activate.ps1`. Docker and Jenkins commands use a POSIX shell.

## Run tests

```sh
python -m pytest -q
ruff check app.py ACEest_Fitness.py tests
docker build --target test -t aceest:test .
bash ci/test-image.sh aceest:test
```

The tests check all three source programs, their pages, the API, unknown programs, health, and version. The container run saves JUnit and coverage XML in `reports/`.

## Run the container

```sh
docker build --target runtime -t aceest:1.0.0 .
docker run --rm -p 127.0.0.1:8000:8000 aceest:1.0.0
```

Open <http://127.0.0.1:8000>. The runtime uses a slim Python image, runs Gunicorn as a non-root user, and excludes the test tools.

## GitHub Actions and Jenkins

GitHub Actions runs on every push and pull request. It builds the test environment, checks Python syntax and lint, builds the runtime image, then runs Pytest inside a container. See the **Actions** tab for the results.

For Jenkins, create a **Pipeline** job. Select **Pipeline script from SCM** and Git. Enter the GitHub URL, choose the `assignment-1` branch (or `main` in an Assignment 1-only repository), and set the script path to `Jenkinsfile`. Use a trusted Unix agent with label `docker` and working Git, Bash, and Docker. Install the Pipeline, Git, JUnit, and Timestamper plugins. Select **Build Now** once to register the Jenkinsfile triggers. Jenkins polls the branch about every five minutes, cleans the workspace, checks out the commit, builds both images, runs the tests, and records the image ID and test results.

The immutable Git tag for this hand-in is `v1.0.0`. The `assignment-1` branch points to the same snapshot. Use the branch URL when both assignments share a GitHub repository.
