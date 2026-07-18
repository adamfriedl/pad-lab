resource "google_secret_manager_secret" "fec_api_key" {
  secret_id = "pad-lab-fec-api-key"
  project   = var.project_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

# Secret *versions* are added out-of-band (setup.sh / gcloud) so a later
# terraform apply without TF_VAR_fec_api_key cannot destroy the key.
