"""
CHHS Respiratory Virus Dashboard — Bronze → Silver → Gold pipeline.

Source : https://data.chhs.ca.gov/dataset/respiratory-virus-dashboard
API    : CKAN datastore_search (no auth required)
Schedule: Weekly on Monday at 06:00 UTC
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
from google.cloud import bigquery

from common.default_args import BQ_LOCATION, DEFAULT_ARGS, PROJECT_ID

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
RESOURCE_ID = "00a147ba-0410-4699-9e34-fd18bbb7017d"
API_URL = "https://data.chhs.ca.gov/api/3/action/datastore_search"
BRONZE_TABLE = f"{PROJECT_ID}.bronze.chhs_respiratory_virus_raw"


# ---------------------------------------------------------------------------
# DAG
# ---------------------------------------------------------------------------
@dag(
    dag_id="chhs_respiratory_virus_pipeline",
    default_args=DEFAULT_ARGS,
    description="Ingest CHHS Respiratory Virus Dashboard into BigQuery (medallion).",
    schedule="0 6 * * 1",  # every Monday 06:00 UTC
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["chhs", "respiratory", "medallion"],
    template_searchpath=["/home/airflow/gcs/data"],
)
def chhs_respiratory_virus_pipeline():
    # ── Extract ──────────────────────────────────────────────────────────
    @task()
    def extract() -> list[dict]:
        """Fetch all rows from the CHHS Respiratory Virus Dashboard API."""
        all_records: list[dict] = []
        limit = 10_000
        offset = 0

        while True:
            resp = requests.get(
                API_URL,
                params={
                    "resource_id": RESOURCE_ID,
                    "limit": limit,
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
            if len(records) < limit:
                break
            offset += limit

        return all_records

    # ── Load Bronze ──────────────────────────────────────────────────────
    @task()
    def load_bronze(records: list[dict]) -> str:
        """Load raw JSON records into the bronze BigQuery table.

        Every field is stored as STRING so the bronze layer is a faithful
        copy of the source. Metadata columns are added for lineage.
        """
        batch_id = str(uuid.uuid4())
        ingestion_ts = datetime.utcnow().isoformat()

        rows = []
        for rec in records:
            row = {k: str(v) if v is not None else None for k, v in rec.items()}
            row["_ingestion_timestamp"] = ingestion_ts
            row["_batch_id"] = batch_id
            # Drop the CKAN internal row id
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
        job.result()  # block until complete
        return f"Loaded {len(rows)} rows into {BRONZE_TABLE}"

    # ── Silver ───────────────────────────────────────────────────────────
    silver = BigQueryInsertJobOperator(
        task_id="transform_silver",
        configuration={
            "query": {
                "query": "{% include 'sql/silver/clean_respiratory_virus.sql' %}",
                "useLegacySql": False,
                "destinationTable": {
                    "projectId": PROJECT_ID,
                    "datasetId": "silver",
                    "tableId": "respiratory_virus",
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

    dim_season = BigQueryInsertJobOperator(
        task_id="gold_dim_season",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/dim_season.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    dim_region = BigQueryInsertJobOperator(
        task_id="gold_dim_region",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/dim_region.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    dim_age_group = BigQueryInsertJobOperator(
        task_id="gold_dim_age_group",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/dim_age_group.sql' %}",
                "useLegacySql": False,
            }
        },
        project_id=PROJECT_ID,
        location=BQ_LOCATION,
        deferrable=True,
    )

    # ── Gold: Fact (MERGE/upsert) ────────────────────────────────────────
    fact = BigQueryInsertJobOperator(
        task_id="gold_fact_respiratory_metrics",
        configuration={
            "query": {
                "query": "{% include 'sql/gold/fact_respiratory_metrics.sql' %}",
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
    bronze_done >> silver >> init_gold >> [dim_date, dim_season, dim_region, dim_age_group] >> fact


chhs_respiratory_virus_pipeline()
