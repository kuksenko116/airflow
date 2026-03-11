# ---------------------------------------------------------------------------
# BigQuery Datasets — medallion architecture (bronze → silver → gold)
# ---------------------------------------------------------------------------
locals {
  bq_datasets = ["bronze", "silver", "gold"]
}

resource "google_bigquery_dataset" "medallion" {
  for_each = toset(local.bq_datasets)

  project    = google_project.this.project_id
  dataset_id = each.value
  location   = var.region

  access {
    role          = "WRITER"
    user_by_email = google_service_account.composer_worker.email
  }

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }

  depends_on = [time_sleep.api_propagation]
}
