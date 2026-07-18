output "project_id" {
  value = var.project_id
}

output "landing_bucket" {
  value = google_storage_bucket.landing.url
}

output "raw_dataset" {
  value = "${var.project_id}.${google_bigquery_dataset.raw.dataset_id}"
}

output "staging_dataset" {
  value = "${var.project_id}.${google_bigquery_dataset.staging.dataset_id}"
}

output "mart_dataset" {
  value = "${var.project_id}.${google_bigquery_dataset.mart.dataset_id}"
}

output "pipeline_sa_email" {
  value = google_service_account.pipeline.email
}

output "scheduler_sa_email" {
  value = google_service_account.scheduler.email
}

output "artifact_registry_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pad_lab.repository_id}"
}

output "pipeline_image" {
  value = local.pipeline_image
}

output "cloud_run_job" {
  value = google_cloud_run_v2_job.pipeline.name
}

output "scheduler_job" {
  value = google_cloud_scheduler_job.pipeline.name
}

output "fec_secret_id" {
  value = google_secret_manager_secret.fec_api_key.secret_id
}

output "alert_email_configured" {
  value = var.alert_email != ""
}

output "project_budget_configured" {
  value = var.billing_account_id != ""
}
