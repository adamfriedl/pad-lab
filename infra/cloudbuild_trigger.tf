# Rebuild pipeline image when ingest/transform code changes on main.
# Requires a one-time Cloud Build ↔ GitHub App connection for this repo
# (Cloud Build console → Triggers → Connect repository; region must match var.region).
resource "google_cloudbuild_trigger" "pipeline_image" {
  name        = "pad-lab-pipeline-image"
  project     = var.project_id
  location    = var.region
  description = "Build/push pipeline:latest on main (loaders, dbt, Dockerfile, scripts)"

  github {
    owner = var.pipeline_github_owner
    name  = var.pipeline_github_repo
    push {
      branch = "^${var.pipeline_github_branch}$"
    }
  }

  included_files = [
    "loaders/**",
    "dbt/**",
    "Dockerfile",
    "scripts/**",
    "requirements.txt",
    "cloudbuild.yaml",
  ]

  filename = "cloudbuild.yaml"

  # Regional triggers require a user-managed SA (not {PROJECT_NUMBER}@cloudbuild.gserviceaccount.com).
  service_account = google_service_account.cloudbuild.id

  substitutions = {
    _REGION = var.region
    _IMAGE  = local.pipeline_image
    _CACHE  = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pad_lab.repository_id}/pipeline:buildcache"
  }

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository_iam_member.cloudbuild_writer,
    google_project_iam_member.cloudbuild_builder,
    google_project_iam_member.cloudbuild_logs_writer,
    google_service_account_iam_member.cloudbuild_agent_act_as,
  ]
}
