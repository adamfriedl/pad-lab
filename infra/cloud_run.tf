resource "google_cloud_run_v2_job" "pipeline" {
  name                = "pad-lab-pipeline"
  location            = var.region
  project             = var.project_id
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.pipeline.email
      timeout         = "1800s"
      max_retries     = 1

      containers {
        image = local.pipeline_image

        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }

        env {
          name  = "GCP_REGION"
          value = var.bq_location
        }

        env {
          name  = "MAX_RECORDS"
          value = tostring(var.max_records)
        }

        env {
          name  = "LOOKBACK_DAYS"
          value = tostring(var.lookback_days)
        }

        env {
          name = "FEC_API_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.fec_api_key.secret_id
              version = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.pad_lab,
    google_secret_manager_secret_iam_member.pipeline_fec_key,
  ]

  lifecycle {
    # Image digests change on each build; ignore tag churn after first create.
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# Ensure Cloud Scheduler service agent exists before IAM bindings.
resource "google_project_service_identity" "cloudscheduler" {
  provider = google-beta
  project  = var.project_id
  service  = "cloudscheduler.googleapis.com"

  depends_on = [google_project_service.apis]
}

# Allow Cloud Scheduler service agent to impersonate the scheduler SA
resource "google_service_account_iam_member" "scheduler_sa_user_by_scheduler_agent" {
  service_account_id = google_service_account.scheduler.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_project_service_identity.cloudscheduler.email}"
}

resource "google_cloud_scheduler_job" "pipeline" {
  name             = "pad-lab-pipeline-daily"
  description      = "Daily Cloud Build (cached image rebuild) + FEC ingest + dbt run"
  schedule         = var.pipeline_schedule
  time_zone        = "UTC"
  attempt_deadline = "1800s"
  region           = var.region
  project          = var.project_id

  retry_config {
    retry_count = 1
  }

  http_target {
    http_method = "POST"
    uri         = "https://cloudbuild.googleapis.com/v1/projects/${var.project_id}/builds"

    headers = {
      "Content-Type" = "application/json"
    }

    body = base64encode(jsonencode({
      source = {
        gitSource = {
          url      = "https://github.com/${var.pipeline_github_owner}/${var.pipeline_github_repo}"
          revision = "refs/heads/${var.pipeline_github_branch}"
        }
      }
      filename = "cloudbuild.yaml"
      substitutions = {
        _REGION  = var.region
        _IMAGE   = local.pipeline_image
        _JOB     = google_cloud_run_v2_job.pipeline.name
        _RUN_JOB = "true"
      }
      options = {
        logging = "CLOUD_LOGGING_ONLY"
      }
      timeout = "1800s"
    }))

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  depends_on = [
    google_project_service.apis,
    google_project_iam_member.scheduler_cloudbuild_editor,
    google_cloud_run_v2_job_iam_member.cloudbuild_job_runner,
    google_service_account_iam_member.scheduler_sa_user_by_scheduler_agent,
  ]
}
