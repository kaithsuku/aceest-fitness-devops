import pytest

from app import create_app


@pytest.fixture
def client():
    return create_app().test_client()


def test_home_lists_all_programs(client):
    response = client.get("/")
    assert response.status_code == 200
    for code in ("fl", "mg", "bg"):
        assert f'href="./programs/{code}"'.encode() in response.data


@pytest.mark.parametrize(
    ("code", "name", "workout", "nutrition"),
    [
        ("fl", "Fat Loss (FL)", "Back Squat", "2,000 kcal"),
        ("mg", "Muscle Gain (MG)", "Barbell Rows", "3,200 kcal"),
        ("bg", "Beginner (BG)", "Air Squats", "120g/day"),
    ],
)
def test_program_matches_supplied_catalog(client, code, name, workout, nutrition):
    response = client.get(f"/api/programs/{code}")
    assert response.status_code == 200
    program = response.get_json()
    assert program["name"] == name
    assert workout in program["workout"]
    assert nutrition in program["nutrition"]
    page = client.get(f"/programs/{code}")
    assert page.status_code == 200
    assert workout.encode() in page.data
    assert nutrition.encode() in page.data


def test_program_api_lists_unique_codes(client):
    response = client.get("/api/programs")
    assert response.status_code == 200
    assert [program["code"] for program in response.get_json()] == ["fl", "mg", "bg"]


def test_unknown_program_returns_404(client):
    assert client.get("/api/programs/unknown").status_code == 404
    assert client.get("/programs/unknown").status_code == 404


def test_service_health(client):
    assert client.get("/healthz").get_json() == {"status": "ok"}


def test_version_matches_release_file(client):
    from pathlib import Path

    assert client.get("/version").get_json() == {
        "version": (Path(__file__).parents[1] / "VERSION").read_text().strip()
    }
