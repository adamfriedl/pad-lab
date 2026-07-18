resource "google_artifact_registry_repository" "pad_lab" {
  project       = var.project_id
  location      = var.region
  repository_id = "pad-lab"
  description   = "PAD lab pipeline container images"
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

locals {
  pipeline_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pad_lab.repository_id}/pipeline:${var.pipeline_image_tag}"
}
