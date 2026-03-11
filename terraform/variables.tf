variable "project_id" {
  description = "GCP project ID to create (must be globally unique)."
  type        = string
}

variable "billing_account_id" {
  description = "Billing account ID to link to the project (format: XXXXXX-XXXXXX-XXXXXX)."
  type        = string
}

variable "folder_id" {
  description = "GCP folder ID under which the project is created (numeric, no 'folders/' prefix). Leave empty if no folder."
  type        = string
  default     = ""
}

variable "org_id" {
  description = "GCP organization ID. Leave empty for personal accounts without an organization."
  type        = string
  default     = ""
}

variable "region" {
  description = "GCP region for all resources."
  type        = string
  default     = "us-central1"
}

variable "composer_image_version" {
  description = "Cloud Composer 3 image version. See: https://cloud.google.com/composer/docs/concepts/versioning/composer-versions"
  type        = string
  default     = "composer-3-airflow-2.10.5-build.3"
}
