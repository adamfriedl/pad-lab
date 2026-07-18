# Optional project-scoped billing budget — separate from any account-wide budget
# you already have. Filters spend to this GCP project only.
resource "google_billing_budget" "pad_lab" {
  count = var.billing_account_id != "" ? 1 : 0

  billing_account = "billingAccounts/${var.billing_account_id}"
  display_name    = "pad-lab (${var.project_id})"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.5
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.9
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.0
    spend_basis       = "FORECASTED_SPEND"
  }

  dynamic "all_updates_rule" {
    for_each = var.alert_email != "" ? [1] : []
    content {
      monitoring_notification_channels = [
        google_monitoring_notification_channel.email[0].id,
      ]
      disable_default_iam_recipients = false
    }
  }

  depends_on = [google_project_service.apis]
}
