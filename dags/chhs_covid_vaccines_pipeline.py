"""
CHHS COVID-19 Vaccines by County — Bronze → Silver → Gold pipeline.

Source : https://data.chhs.ca.gov/dataset/vaccine-progress-dashboard
API    : CKAN datastore_search (no auth required, paginated)
Schedule: Daily at 07:00 UTC
Strategy: Full reload (WRITE_TRUNCATE)
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
RESOURCE_ID = "130d7ba2-b6eb-438d-a412-741bde207e1c"
API_URL = "https://data.chhs.ca.gov/api/3/action/datastore_search"
PAGE_SIZE = 10_000
BRONZE_TABLE = f"{PROJECT_ID}.bronze.chhs_covid_vaccines_raw"


# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
@dag(
    dag_id="chhs_covid_vaccines_pipeline",
    default_args=DEFAULT_ARGS,
    description="Ingest CHHS COVID-19 Vaccines by County into BigQuery (medallion).",
    schedule="0 7 * * *",  # daily 07:00 UTC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["chhs", "covid", "vaccines", "medallion"],
    template_searchpath=["/home/airflow/gcs/data"],
)
def chhs_covid_vaccines_pipeline():
    # ── Extract (paginated) ──────────────────────────────────────────────
    @task()
    def extract() -> list[dict]:
        """Fetch all rows from the COVID-19 Vaccines API with pagination."""
        all_records: list[dict] = []
        offset = 0

        while True:
            resp = requests.get(
                API_URL,
                params={
                    "resource_id": RESOURCE_ID,
                    "limit": PAGE_SIZE,
                    "offset": offset,
                },
                timeout=120,
            )
            resp.raise_for_status()
            result = resp.json()["result"]
            records = result["records"]
            if not records:
                break
            all_records.extend(records)
            if len(records) < PAGE_SIZE:
                break
            offset += PAGE_SIZE

        return all_records

    # ── Load Bronze ──────────────────────────────────────────────────────
    @task()
    def load_bronze(records: list[dict]) -> str:
        """Load raw records into bronze, casting every value to STRING."""
        batch_id = str(uuid.uuid4())
        ingestion_ts = datetime.utcnow().isoformat()

        rows = []
        for rec in records:
            row = {k: str(v) if v is not None else None for k, v in rec.items()}
            row["_ingestion_timestamp"] = ingestion_ts
            row["_batch_id"] = batch_id
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

    # ── Silver ───────────────────────────────────────────────────────────
    silver = BigQueryInsertJobOperator(
        task_id="transform_silver",
        configuration={
            "query": {
                "query": "{% include 'sql/silver/clean_covid_vaccines.sql' %}",
                "useLegacySql": False,
                "destinationTable": {
                    "projectId": PROJECT_ID,
                    "datasetId": "silver",
                    "tableId": "covid_vaccines_by_county",
                },
                "writeDisposition": "WRITE_TRUNCATE",
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

    # ── Gold: Dimensions (MERGE/upsert) ──────────────────────────────────
    dim_date = BigQueryInsertJobOperator(
        task_id="gold_dim_date",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/dim_date.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    dim_county = BigQueryInsertJobOperator(
        task_id="gold_dim_county",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/dim_county.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Gold: Fact (MERGE/upsert) ────────────────────────────────────────
    fact = BigQueryInsertJobOperator(
        task_id="gold_fact_covid_vaccination_summary",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/fact_covid_vaccination_summary.sql' %}",
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
    bronze_done >> silver >> init_gold >> [dim_date, dim_county] >> fact


chhs_covid_vaccines_pipeline()
