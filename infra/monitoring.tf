resource "google_monitoring_notification_channel" "email" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "PAD lab email"
  type         = "email"
  project      = var.project_id

  labels = {
    email_address = var.alert_email
  }

  depends_on = [google_project_service.apis]
}

# Fire when a Cloud Run Job execution completes with a failed result.
resource "google_monitoring_alert_policy" "pipeline_job_failed" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "PAD lab pipeline job failed"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "Cloud Run Job failed execution"

    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_job"
        AND resource.labels.job_name = "${google_cloud_run_v2_job.pipeline.name}"
        AND metric.type = "run.googleapis.com/job/completed_execution_count"
        AND metric.labels.result = "failed"
      EOT

      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"

      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_DELTA"
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].id,
  ]

  alert_strategy {
    auto_close = "1800s"
  }

  documentation {
    content   = "pad-lab Cloud Run Job failed. Check Cloud Run → Jobs → pad-lab-pipeline logs, then FEC API / dbt test output."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.apis]
}

# Fire if the rolling freshness_hours window has zero successes for freshness_grace_minutes.
# Metric-absence conditions cap at 23h30m, which false-alarms on a 24h schedule; use a 24h
# ALIGN_DELTA sum instead, with grace so the daily run can finish before we page.
resource "google_monitoring_alert_policy" "pipeline_stale" {
  count = var.alert_email != "" ? 1 : 0

  display_name = "PAD lab pipeline stale (no successful run)"
  project      = var.project_id
  combiner     = "OR"

  conditions {
    display_name = "No successful Cloud Run Job execution"

    condition_threshold {
      filter = <<-EOT
        resource.type = "cloud_run_job"
        AND resource.labels.job_name = "${google_cloud_run_v2_job.pipeline.name}"
        AND metric.type = "run.googleapis.com/job/completed_execution_count"
        AND metric.labels.result = "succeeded"
      EOT

      comparison      = "COMPARISON_LT"
      threshold_value = 1
      duration        = "${var.freshness_grace_minutes * 60}s"

      aggregations {
        alignment_period     = "${var.freshness_hours * 3600}s"
        per_series_aligner   = "ALIGN_DELTA"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = []
      }

      trigger {
        count = 1
      }
    }
  }

  notification_channels = [
    google_monitoring_notification_channel.email[0].id,
  ]

  alert_strategy {
    auto_close = "3600s"
  }

  documentation {
    content   = "No successful pad-lab pipeline run in ${var.freshness_hours}h (confirmed for ${var.freshness_grace_minutes}m). Check Cloud Scheduler (pad-lab-pipeline-daily) → Cloud Run Job executions."
    mime_type = "text/markdown"
  }

  depends_on = [google_project_service.apis]
}
