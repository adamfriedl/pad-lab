resource "google_service_account" "pipeline" {
  account_id   = "pad-lab-pipeline"
  display_name = "PAD lab pipeline (runtime)"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_service_account" "scheduler" {
  account_id   = "pad-lab-scheduler"
  display_name = "PAD lab scheduler (trigger only)"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

# User-managed SA for regional Cloud Build triggers (default @cloudbuild.gserviceaccount.com is rejected).
resource "google_service_account" "cloudbuild" {
  account_id   = "pad-lab-cloudbuild"
  display_name = "PAD lab Cloud Build (image trigger)"
  project      = var.project_id

  depends_on = [google_project_service.apis]
}

resource "google_project_iam_member" "cloudbuild_builder" {
  project = var.project_id
  role    = "roles/cloudbuild.builds.builder"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_project_iam_member" "cloudbuild_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloudbuild.email}"
}

# Cloud Build service agent must impersonate the user-managed SA when a trigger runs.
resource "google_service_account_iam_member" "cloudbuild_agent_act_as" {
  service_account_id = google_service_account.cloudbuild.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:service-${data.google_project.current.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"
}

# Pipeline SA: run BigQuery jobs
resource "google_project_iam_member" "pipeline_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# Pipeline SA: edit data in lab datasets
resource "google_bigquery_dataset_iam_member" "pipeline_raw" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_staging" {
  dataset_id = google_bigquery_dataset.staging.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_mart" {
  dataset_id = google_bigquery_dataset.mart.dataset_id
  project    = var.project_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}

# Pipeline SA: write landing zone
resource "google_storage_bucket_iam_member" "pipeline_landing" {
  bucket = google_storage_bucket.landing.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# Pipeline SA: read FEC API key
resource "google_secret_manager_secret_iam_member" "pipeline_fec_key" {
  secret_id = google_secret_manager_secret.fec_api_key.secret_id
  project   = var.project_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.pipeline.email}"
}

# Scheduler SA: execute the Cloud Run Job (no image rebuild)
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.pipeline.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Build needs to push images to Artifact Registry (trigger SA + manual gcloud builds submit).
resource "google_artifact_registry_repository_iam_member" "cloudbuild_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.pad_lab.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloudbuild.email}"
}

resource "google_artifact_registry_repository_iam_member" "cloudbuild_legacy_writer" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.pad_lab.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"
}

data "google_project" "current" {
  project_id = var.project_id
}
