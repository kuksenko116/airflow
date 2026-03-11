# ---------------------------------------------------------------------------
# Cloud Composer 3 Environment
# ---------------------------------------------------------------------------
resource "google_composer_environment" "this" {
  provider = google-beta
  project  = google_project.this.project_id
  name     = "chhs-demo"
  region   = var.region

  config {
    software_config {
      image_version = var.composer_image_version

      pypi_packages = {
        requests = ">=2.31,<3"
      }
    }

    environment_size = "ENVIRONMENT_SIZE_SMALL"

    node_config {
      service_account = google_service_account.composer_worker.email

      network    = google_compute_network.composer.id
      subnetwork = google_compute_subnetwork.composer.id
    }

    workloads_config {
      scheduler {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
        count      = 1
      }

      web_server {
        cpu        = 0.5
        memory_gb  = 2
        storage_gb = 1
      }

      worker {
        cpu        = 1
        memory_gb  = 2
        storage_gb = 1
        min_count  = 1
        max_count  = 2
      }
    }
  }

  depends_on = [
    google_project_iam_member.composer_worker,
    google_bigquery_dataset.medallion,
    time_sleep.api_propagation,
  ]
}
