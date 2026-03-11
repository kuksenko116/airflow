"""Shared configuration used by all DAGs."""

from datetime import timedelta

from airflow.models import Variable

# Pulled from the Airflow Variables UI (or CLI) so DAGs stay portable.
PROJECT_ID = Variable.get("gcp_project_id")

BQ_LOCATION = "us-central1"

DEFAULT_ARGS = {
    "owner": "data-team",
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "execution_timeout": timedelta(minutes=30),
}
