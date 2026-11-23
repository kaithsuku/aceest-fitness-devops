"""Flask entry point for the ACEest Fitness program catalog."""

from dataclasses import asdict
from pathlib import Path

from flask import Flask, abort, render_template, request

from ACEest_Fitness import PROGRAMS, estimate_calories

VERSION = Path(__file__).with_name("VERSION").read_text(encoding="utf-8").strip()


def get_program(code):
    program = PROGRAMS.get(code)
    if program is None:
        abort(404, description="Fitness program not found.")
    return program


def create_app():
    app = Flask(__name__)

    @app.get("/")
    def home():
        return render_template("index.html", programs=PROGRAMS.values(), version=VERSION)

    @app.get("/programs/<code>")
    def program_page(code):
        program = get_program(code)
        weight = request.args.get("weight_kg")
        result = error = None
        if weight is not None:
            try:
                result = estimate_calories(code, weight)["estimated_kcal_per_day"]
            except ValueError as exc:
                error = str(exc)
        return render_template(
            "program.html", program=program, version=VERSION,
            weight=weight, result=result, error=error,
        ), 400 if error else 200

    @app.get("/api/programs")
    def programs_api():
        return [asdict(program) for program in PROGRAMS.values()]

    @app.get("/api/programs/<code>")
    def program_api(code):
        return asdict(get_program(code))

    @app.get("/api/programs/<code>/estimate")
    def estimate_api(code):
        get_program(code)
        try:
            return estimate_calories(code, request.args.get("weight_kg"))
        except ValueError as exc:
            return {"error": str(exc)}, 400

    @app.get("/healthz")
    def health():
        return {"status": "ok"}

    @app.get("/version")
    def version():
        return {"version": VERSION}

    return app
