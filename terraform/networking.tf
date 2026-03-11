# ---------------------------------------------------------------------------
# VPC & Subnet for Cloud Composer
# ---------------------------------------------------------------------------
resource "google_compute_network" "composer" {
  project                 = google_project.this.project_id
  name                    = "composer-network"
  auto_create_subnetworks = false

  depends_on = [time_sleep.api_propagation]
}

resource "google_compute_subnetwork" "composer" {
  project       = google_project.this.project_id
  name          = "composer-subnet"
  region        = var.region
  network       = google_compute_network.composer.id
  ip_cidr_range = "10.0.0.0/24"

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}
