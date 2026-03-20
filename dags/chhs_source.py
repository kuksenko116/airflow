"""
CMS Revoked Medicare Providers & Suppliers — Bronze → Silver → Gold pipeline.

Source  : https://data.cms.gov/provider-characteristics/medicare-provider-supplier-enrollment/revoked-medicare-providers-and-suppliers
API     : CMS Data API v1 (no auth required, paginated via size/offset)
Endpoint: https://data.cms.gov/data-api/v1/dataset/a6496a7d-4e19-479a-a9ad-d4c0a49e07c3/data
Schedule: Weekly on Monday at 06:00 UTC
Strategy: Bronze full reload, Silver/Gold MERGE (upsert)
"""

from __future__ import annotations

import uuid
from datetime import datetime

import requests
from airflow.decorators import dag, task
from airflow.providers.google.cloud.operators.bigquery import (
    BigQueryInsertJobOperator,
)
from common.default_args import BQ_LOCATION, DEFAULT_ARGS, PROJECT_ID
from google.cloud import bigquery

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
DATASET_ID = "a6496a7d-4e19-479a-a9ad-d4c0a49e07c3"
API_URL = f"https://data.cms.gov/data-api/v1/dataset/{DATASET_ID}/data"
PAGE_SIZE = 5_000  # CMS API max page size per docs
BRONZE_TABLE = f"{PROJECT_ID}.bronze.cms_revoked_medicare_providers_raw"


# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
@dag(
    dag_id="cms_revoked_medicare_providers_pipeline",
    default_args=DEFAULT_ARGS,
    description=(
        "Ingest CMS Revoked Medicare Providers and Suppliers data into "
        "BigQuery (bronze → silver → gold medallion)."
    ),
    schedule="0 6 * * 1",  # every Monday 06:00 UTC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["cms", "medicare", "providers", "revoked", "medallion"],
    template_searchpath=["/home/airflow/gcs/data"],
)
def cms_revoked_medicare_providers_pipeline():
    # ── Extract (paginated) ──────────────────────────────────────────────
    @task()
    def extract() -> list[dict]:
        """
        Fetch all rows from the CMS Revoked Medicare Providers API
        using pagination via `size` and `offset`.
        """
        all_records: list[dict] = []
        offset = 0

        while True:
            resp = requests.get(
                API_URL,
                params={
                    "size": PAGE_SIZE,
                    "offset": offset,
                },
                timeout=120,
            )
            resp.raise_for_status()

            # CMS Data API returns a JSON array of row objects
            records = resp.json()
            if not records:
                break

            all_records.extend(records)

            # Stop once we get a short page
            if len(records) < PAGE_SIZE:
                break

            offset += PAGE_SIZE

        return all_records

    # ── Load Bronze ──────────────────────────────────────────────────────
    @task()
    def load_bronze(records: list[dict]) -> str:
        """
        Load raw records into bronze, casting every value to STRING,
        and tagging each row with ingestion metadata.
        """
        if not records:
            return f"No records returned from CMS API for {DATASET_ID}"

        batch_id = str(uuid.uuid4())
        ingestion_ts = datetime.utcnow().isoformat()

        rows: list[dict] = []
        for rec in records:
            row = {k: (str(v) if v is not None else None) for k, v in rec.items()}
            row["_ingestion_timestamp"] = ingestion_ts
            row["_batch_id"] = batch_id

            # Some CMS datasets might include an internal `_id` — drop if present
            row.pop("_id", None)

            rows.append(row)

        client = bigquery.Client(project=PROJECT_ID, location=BQ_LOCATION)
        job_config = bigquery.LoadJobConfig(
            source_format=bigquery.SourceFormat.NEWLINE_DELIMITED_JSON,
            write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
            autodetect=False,
            schema=[bigquery.SchemaField(k, "STRING") for k in rows[0].keys()],
        )

        job = client.load_table_from_json(rows, BRONZE_TABLE, job_config=job_config)
        job.result()

        return f"Loaded {len(rows)} rows into {BRONZE_TABLE}"

    # ── Silver: Init tables ──────────────────────────────────────────────
    init_silver = BigQueryInsertJobOperator(
        task_id="init_silver_tables",
        configuration={
            "query": {
                "query": "{% include 'sql/silver/init_silver_tables.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Silver: MERGE/upsert ──────────────────────────────────────────────
    silver = BigQueryInsertJobOperator(
        task_id="transform_silver",
        configuration={
            "query": {
                "query": "{% include 'sql/silver/clean_cms_revoked_providers.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Gold: Init tables ─────────────────────────────────────────────────
    init_gold = BigQueryInsertJobOperator(
        task_id="init_gold_tables",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/init_gold_tables.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Gold: MERGE/upsert by state ──────────────────────────────────────
    gold_by_state = BigQueryInsertJobOperator(
        task_id="aggregate_gold_by_state",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/revoked_providers_by_state.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Gold: MERGE/upsert trends ────────────────────────────────────────
    gold_trends = BigQueryInsertJobOperator(
        task_id="aggregate_gold_trends",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/revoked_providers_trends.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Dependencies ─────────────────────────────────────────────────────
    raw_data = extract()
    bronze_done = load_bronze(raw_data)
    bronze_done >> init_silver >> silver >> init_gold >> [gold_by_state, gold_trends]


cms_revoked_medicare_providers_pipeline()
