resource "aws_budgets_budget" "monthly_alert" {
  name         = "Monthly-Budget-Alert"
  budget_type  = "COST"
  time_unit    = "MONTHLY"
  limit_amount = var.budget_limit
  limit_unit   = "USD"

  # Alert threshold - 80% of budget
  notification {
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.admin_email]
  }

}
