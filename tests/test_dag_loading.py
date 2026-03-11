"""Smoke tests — verify that every DAG file loads without import errors."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import patch

import pytest
from airflow.models import DagBag

DAGS_DIR = str(Path(__file__).resolve().parent.parent / "dags")


@pytest.fixture(name="dagbag")
def dagbag_fixture():
    """Load all DAGs from the dags/ folder with a mocked PROJECT_ID variable."""
    # Composer adds the dags/ folder to sys.path; replicate that locally.
    if DAGS_DIR not in sys.path:
        sys.path.insert(0, DAGS_DIR)
    with patch.dict(os.environ, {"AIRFLOW_VAR_GCP_PROJECT_ID": "test-project"}):
        bag = DagBag(dag_folder=DAGS_DIR, include_examples=False)
    return bag


def test_no_import_errors(dagbag: DagBag):
    """Every DAG file should parse without errors."""
    assert dagbag.import_errors == {}, f"DAG import errors: {dagbag.import_errors}"


def test_dag_count(dagbag: DagBag):
    """We expect at least 2 DAGs."""
    assert len(dagbag.dags) >= 2


@pytest.mark.parametrize(
    "dag_id",
    [
        "chhs_respiratory_virus_pipeline",
        "chhs_covid_vaccines_pipeline",
    ],
)
def test_dag_has_tags(dagbag: DagBag, dag_id: str):
    """Every DAG should have at least one tag for filtering in the UI."""
    dag = dagbag.dags[dag_id]
    assert dag.tags, f"{dag_id} has no tags"


@pytest.mark.parametrize(
    "dag_id",
    [
        "chhs_respiratory_virus_pipeline",
        "chhs_covid_vaccines_pipeline",
    ],
)
def test_dag_has_retries(dagbag: DagBag, dag_id: str):
    """Default args should include retries > 0."""
    dag = dagbag.dags[dag_id]
    assert dag.default_args.get("retries", 0) > 0, f"{dag_id} has no retries"
