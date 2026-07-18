resource "google_storage_bucket" "landing" {
  name                        = "pad-lab-${var.project_id}"
  location                    = var.bq_location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.apis]
}

# Public JSON snapshots for the GitHub Pages dashboard (separate from landing).
resource "google_storage_bucket" "viz" {
  name                        = "pad-lab-${var.project_id}-viz"
  location                    = var.bq_location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  cors {
    origin          = ["https://adamfriedl.github.io", "https://adamfriedl.net", "http://localhost:5173"]
    method          = ["GET", "HEAD"]
    response_header = ["Content-Type"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket_iam_member" "viz_public_read" {
  bucket = google_storage_bucket.viz.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_iam_member" "pipeline_viz_write" {
  bucket = google_storage_bucket.viz.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_bigquery_dataset" "raw" {
  dataset_id                 = "pad_lab_raw"
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "staging" {
  dataset_id                 = "pad_lab_staging"
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}

resource "google_bigquery_dataset" "mart" {
  dataset_id                 = "pad_lab_mart"
  project                    = var.project_id
  location                   = var.bq_location
  delete_contents_on_destroy = true

  depends_on = [google_project_service.apis]
}
