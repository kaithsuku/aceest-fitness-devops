"""Check a version endpoint and an original program through the service."""

import json
import sys
import time
from urllib.request import urlopen


def read_json(url):
    with urlopen(url, timeout=4) as response:
        return json.load(response)


def check_service(base, version):
    for attempt in range(25):
        try:
            actual = read_json(f"{base}/version")["version"]
            program = read_json(f"{base}/api/programs/fl")
            if actual == version and program["code"] == "fl":
                print(f"{base} serves release {version}")
                return
            print(f"{base} returned release {actual}. Waiting for {version}.", file=sys.stderr)
        except (OSError, ValueError, KeyError) as exc:
            print(f"{base} attempt {attempt + 1}: {exc}", file=sys.stderr)
        time.sleep(1)
    raise SystemExit(f"{base} did not serve release {version}")


if __name__ == "__main__":
    check_service(sys.argv[1], sys.argv[2])
