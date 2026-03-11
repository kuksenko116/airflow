output "project_id" {
  description = "GCP project ID."
  value       = google_project.this.project_id
}

output "composer_dag_gcs_prefix" {
  description = "GCS path to upload DAGs to."
  value       = google_composer_environment.this.config[0].dag_gcs_prefix
}

output "airflow_uri" {
  description = "Airflow web UI URL."
  value       = google_composer_environment.this.config[0].airflow_uri
}

output "gcs_bucket" {
  description = "Composer environment GCS bucket (without gs:// prefix)."
  value       = replace(google_composer_environment.this.config[0].dag_gcs_prefix, "/dags", "")
}
