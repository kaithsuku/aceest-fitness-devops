"""Save gate results and measures for the current Jenkins analysis."""

import json
import os
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def read_api(path, **params):
    base = os.environ["SONAR_HOST_URL"].rstrip("/")
    token = os.environ["SONAR_TOKEN"]
    request = Request(f"{base}/{path}?{urlencode(params)}",
                      headers={"Authorization": f"Bearer {token}"})
    with urlopen(request, timeout=20) as response:
        return json.load(response)


def main():
    metadata = dict(
        line.split("=", 1)
        for line in Path(".scannerwork/report-task.txt").read_text().splitlines()
        if "=" in line
    )
    task = read_api("api/ce/task", id=metadata["ceTaskId"])["task"]
    gate = read_api(
        "api/qualitygates/project_status", analysisId=task["analysisId"]
    )["projectStatus"]
    measures = read_api(
        "api/measures/component",
        component=metadata["projectKey"],
        metricKeys="coverage,ncloc,duplicated_lines_density,violations",
    )["component"]["measures"]
    report = {
        "project": metadata["projectKey"],
        "analysis_id": task["analysisId"],
        "analysis_date": task.get("executedAt"),
        "quality_gate": gate,
        "measures": {metric["metric"]: metric["value"] for metric in measures},
    }
    Path("reports/sonarqube.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f'SonarQube gate status: {gate["status"]}')
    if gate["status"] != "OK":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
