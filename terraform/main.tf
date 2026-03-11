terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# ---------------------------------------------------------------------------
# GCP Project
# ---------------------------------------------------------------------------
resource "google_project" "this" {
  name                = var.project_id
  project_id          = var.project_id
  billing_account     = var.billing_account_id
  folder_id           = var.folder_id != "" ? var.folder_id : null
  org_id              = var.org_id != "" ? var.org_id : null
  deletion_policy     = "DELETE"
  auto_create_network = false
}

# ---------------------------------------------------------------------------
# Enable required APIs
# ---------------------------------------------------------------------------
locals {
  apis = [
    "composer.googleapis.com",
    "bigquery.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each = toset(local.apis)

  project            = google_project.this.project_id
  service            = each.value
  disable_on_destroy = false
}

# Give APIs time to propagate before downstream resources are created.
resource "time_sleep" "api_propagation" {
  depends_on      = [google_project_service.apis]
  create_duration = "60s"
}
