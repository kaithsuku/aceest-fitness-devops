"""Verify all routes against a running gateway."""

import json
import sys
from collections import Counter
from urllib.request import Request, urlopen


def version(base, route, headers=None, query=""):
    request = Request(f"{base}/{route}/version{query}", headers=headers or {})
    with urlopen(request, timeout=5) as response:
        return json.load(response)["version"]


def check_split(base, route, header, stable, candidate, expected_range):
    results = Counter()
    for identity in range(160):
        headers = {header: f"demo-{identity}"}
        actual = version(base, route, headers)
        if identity < 8:
            assert actual == version(base, route, headers), f"{route}: cohort changed"
        results[actual] += 1
    assert not (results.keys() - {stable, candidate}), (route, results)
    assert results[candidate] in expected_range, (route, results)
    print(f"{route}: {dict(results)}")


def main(base, stable, candidate, marker):
    assert version(base, "blue-green") == candidate
    assert version(base, "rolling") == candidate
    assert version(base, "shadow", query=f"?shadow_probe={marker}") == stable
    if stable == candidate:
        assert version(base, "canary") == stable
        assert version(base, "ab") == stable
    else:
        check_split(base, "canary", "X-Demo-Request", stable, candidate, range(5, 36))
        check_split(base, "ab", "X-Demo-User", stable, candidate, range(50, 111))
    print(f"Blue-green and rolling serve {candidate}. Shadow responds with {stable}.")


if __name__ == "__main__":
    main(*sys.argv[1:])
