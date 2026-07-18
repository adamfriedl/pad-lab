resource "google_storage_bucket" "landing" {
  name                        = "pad-lab-${var.project_id}"
  location                    = var.bq_location
  project                     = var.project_id
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.apis]
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
