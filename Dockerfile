FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /opt/aceest
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY ACEest_Fitness.py app.py VERSION ./
COPY templates/ templates/

FROM base AS test
COPY requirements-dev.txt .coveragerc ./
RUN pip install --no-cache-dir -r requirements-dev.txt
COPY tests/ tests/
USER 10001:10001
CMD ["python", "-m", "pytest", "-p", "no:cacheprovider", "-q"]

FROM base AS runtime
USER 10001:10001
EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "app:create_app()"]
