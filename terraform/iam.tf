# ---------------------------------------------------------------------------
# Service Account for Cloud Composer workers
# ---------------------------------------------------------------------------
resource "google_service_account" "composer_worker" {
  project      = google_project.this.project_id
  account_id   = "composer-worker"
  display_name = "Cloud Composer Worker"

  depends_on = [time_sleep.api_propagation]
}

locals {
  composer_worker_roles = [
    "roles/composer.worker",
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
  ]
}

resource "google_project_iam_member" "composer_worker" {
  for_each = toset(local.composer_worker_roles)

  project = google_project.this.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.composer_worker.email}"
}
