# syntax=docker/dockerfile:1
FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY loaders/ loaders/
COPY dbt/ dbt/
COPY scripts/pipeline_entrypoint.sh scripts/pipeline_entrypoint.sh

# Drop local profiles; entrypoint writes ADC-based profile at runtime.
RUN rm -f dbt/profiles.yml \
    && chmod +x scripts/pipeline_entrypoint.sh

ENV PYTHONUNBUFFERED=1
ENV GCP_PROJECT=""
ENV GCP_REGION=US
ENV MAX_RECORDS=10000
ENV LOOKBACK_DAYS=7

ENTRYPOINT ["/app/scripts/pipeline_entrypoint.sh"]
