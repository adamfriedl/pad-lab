variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Regional resources (Cloud Run, Artifact Registry, Scheduler)"
  type        = string
  default     = "us-central1"
}

variable "bq_location" {
  description = "BigQuery / multi-region GCS location"
  type        = string
  default     = "US"
}

variable "alert_email" {
  description = "Email for pipeline failure / freshness alerts"
  type        = string
  default     = ""
}

variable "pipeline_schedule" {
  description = "Cron schedule for the daily pipeline (UTC)"
  type        = string
  default     = "0 14 * * *"
}

variable "pipeline_image_tag" {
  description = "Container image tag for the Cloud Run Job"
  type        = string
  default     = "latest"
}

variable "freshness_hours" {
  description = "Alert if no successful Cloud Run Job execution within this many hours (max 24 for Monitoring absence conditions)"
  type        = number
  default     = 24

  validation {
    condition     = var.freshness_hours >= 1 && var.freshness_hours <= 24
    error_message = "freshness_hours must be between 1 and 24 (Cloud Monitoring absence duration limit)."
  }
}

variable "max_records" {
  description = "Default FEC contribution fetch limit for scheduled runs"
  type        = number
  default     = 10000
}

variable "lookback_days" {
  description = "Overlap days when fetching since raw high-water mark"
  type        = number
  default     = 7
}

variable "billing_account_id" {
  description = "Billing account ID (012345-678901-ABCDEF). If set, creates a project-scoped monthly budget separate from account-wide budgets."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  description = "Monthly USD cap for the pad-lab project budget (when billing_account_id is set)"
  type        = number
  default     = 25
}
