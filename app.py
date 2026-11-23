"""Flask entry point for the ACEest Fitness program catalog."""

from dataclasses import asdict
from pathlib import Path

from flask import Flask, abort, render_template

from ACEest_Fitness import PROGRAMS

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
        return render_template("program.html", program=get_program(code), version=VERSION)

    @app.get("/api/programs")
    def programs_api():
        return [asdict(program) for program in PROGRAMS.values()]

    @app.get("/api/programs/<code>")
    def program_api(code):
        return asdict(get_program(code))

    @app.get("/healthz")
    def health():
        return {"status": "ok"}

    @app.get("/version")
    def version():
        return {"version": VERSION}

    return app
