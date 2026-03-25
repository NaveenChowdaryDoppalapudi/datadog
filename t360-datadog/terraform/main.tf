################################################################################
# T360 Datadog Monitoring - Terraform Configuration
# Cluster: zuse1-d003-b066-aks-p1-t360-b
################################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.39"
    }
  }

  # Configure your backend - example with Azure Storage
  # backend "azurerm" {
  #   resource_group_name  = "zuse1-d003-b066-rgp-p1-t360-terraform"
  #   storage_account_name = "use1stap1t360tfstate"
  #   container_name       = "tfstate"
  #   key                  = "datadog-monitoring.tfstate"
  # }
}

provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = var.datadog_api_url
  validate = true
}

# ──────────────────────────────────────────────────────────────────────────────
# Local values used across all modules
# ──────────────────────────────────────────────────────────────────────────────
locals {
  common_tags = [
    "env:${var.environment}",
    "app:t360",
    "cluster:${var.aks_cluster_name}",
    "managed-by:terraform",
    "team:${var.team_name}"
  ]

  # Notification handles
  alert_channel     = var.slack_alert_channel
  pagerduty_channel = var.pagerduty_service
  dba_channel       = var.slack_dba_channel
  dba_pagerduty     = var.pagerduty_dba_service
}
