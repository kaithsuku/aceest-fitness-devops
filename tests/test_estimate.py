import pytest

from app import create_app


@pytest.fixture
def client():
    return create_app().test_client()


@pytest.mark.parametrize(("program", "expected"), [("fl", 1540), ("mg", 2450), ("bg", 1820)])
def test_calorie_estimate_uses_supplied_version_1_1_factor(client, program, expected):
    response = client.get(f"/api/programs/{program}/estimate?weight_kg=70")
    assert response.status_code == 200
    assert response.get_json() == {
        "program": program, "weight_kg": 70.0, "estimated_kcal_per_day": expected
    }


@pytest.mark.parametrize("weight", ["", "-1", "0", "bad", "nan", "inf", "501"])
def test_invalid_weight_returns_400(client, weight):
    response = client.get("/api/programs/fl/estimate", query_string={"weight_kg": weight})
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_unknown_estimate_program_returns_404(client):
    assert client.get("/api/programs/unknown/estimate?weight_kg=70").status_code == 404


def test_program_page_shows_estimate(client):
    response = client.get("/programs/fl?weight_kg=70")
    assert response.status_code == 200
    assert b"1540 kcal per day" in response.data


def test_program_page_keeps_details_when_estimate_is_invalid(client):
    response = client.get("/programs/fl?weight_kg=bad")
    assert response.status_code == 400
    assert b"Back Squat" in response.data
    assert b"Enter a weight" in response.data
