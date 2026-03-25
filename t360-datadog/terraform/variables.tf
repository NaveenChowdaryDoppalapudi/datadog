################################################################################
# T360 Datadog Monitoring - Variables
################################################################################

# ──────────────────────────────────────────────────────────────────────────────
# Datadog Authentication
# ──────────────────────────────────────────────────────────────────────────────
variable "datadog_api_key" {
  description = "Datadog API key"
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog Application key"
  type        = string
  sensitive   = true
}

variable "datadog_api_url" {
  description = "Datadog API URL"
  type        = string
  default     = "https://api.datadoghq.com/"
}

# ──────────────────────────────────────────────────────────────────────────────
# Environment Configuration
# ──────────────────────────────────────────────────────────────────────────────
variable "environment" {
  description = "Environment name (production, staging, dev)"
  type        = string
  default     = "production"
}

variable "team_name" {
  description = "Team name for tagging"
  type        = string
  default     = "ipm-ops"
}

# ──────────────────────────────────────────────────────────────────────────────
# Infrastructure Identifiers
# ──────────────────────────────────────────────────────────────────────────────
variable "aks_cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "zuse1-d003-b066-aks-p1-t360-b"
}

variable "aks_resource_group" {
  description = "AKS resource group"
  type        = string
  default     = "zuse1-d003-b066-rgp-p1-t360-aks-b"
}

variable "azure_subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = "0c35e14b-268d-4cb6-8b2d-b8c5d8dc2ace"
}

variable "storage_resource_group" {
  description = "Storage account resource group"
  type        = string
  default     = "zuse1-d003-b066-rgp-p1-t360-storage"
}

variable "storage_account_name" {
  description = "Azure storage account name for file share"
  type        = string
  default     = "use1stap1t360"
}

variable "file_share_name" {
  description = "Azure file share name"
  type        = string
  default     = "t360-prd-share"
}

variable "itp_server_hostname" {
  description = "ITP server FQDN"
  type        = string
  default     = "zuse1p1t360itp1.wkrainier.com"
}

# ──────────────────────────────────────────────────────────────────────────────
# Server Hostnames for Synthetics
# ──────────────────────────────────────────────────────────────────────────────
variable "ftp_server_host" {
  description = "FTP server hostname or IP"
  type        = string
}

variable "ftp_server_port" {
  description = "FTP server port"
  type        = number
  default     = 21
}

variable "smtp_server_host" {
  description = "SMTP server hostname or IP"
  type        = string
}

variable "smtp_server_port" {
  description = "SMTP server port"
  type        = number
  default     = 587
}

# ──────────────────────────────────────────────────────────────────────────────
# Threshold Configuration
# ──────────────────────────────────────────────────────────────────────────────
variable "thresholds" {
  description = "Alert thresholds for all monitors"
  type = object({
    pod_min_running           = number
    disk_warning_pct          = number
    disk_critical_pct         = number
    aks_node_cpu_warning      = number
    aks_node_cpu_critical     = number
    aks_node_memory_warning   = number
    aks_node_memory_critical  = number
    aks_disk_warning_pct      = number
    aks_disk_critical_pct     = number
    db_cpu_warning            = number
    db_cpu_critical           = number
    db_blocking_warning       = number
    db_blocking_critical      = number
    replication_lag_warning_s = number
    replication_lag_critical_s = number
    file_share_warning_bytes  = number
    file_share_critical_bytes = number
    ephemeral_ports_warning   = number
    ephemeral_ports_critical  = number
    msmq_warning              = number
    msmq_critical             = number
  })
  default = {
    pod_min_running           = 1
    disk_warning_pct          = 85
    disk_critical_pct         = 95
    aks_node_cpu_warning      = 80
    aks_node_cpu_critical     = 90
    aks_node_memory_warning   = 80
    aks_node_memory_critical  = 90
    aks_disk_warning_pct      = 75
    aks_disk_critical_pct     = 85
    db_cpu_warning            = 80
    db_cpu_critical           = 90
    db_blocking_warning       = 5
    db_blocking_critical      = 10
    replication_lag_warning_s = 30
    replication_lag_critical_s = 60
    file_share_warning_bytes  = 3848290697216  # 3.5 TB
    file_share_critical_bytes = 4398046511104  # 4.0 TB
    ephemeral_ports_warning   = 6000
    ephemeral_ports_critical  = 4000
    msmq_warning              = 1
    msmq_critical             = 5
  }
}

# ──────────────────────────────────────────────────────────────────────────────
# Notification Channels
# ──────────────────────────────────────────────────────────────────────────────
variable "slack_alert_channel" {
  description = "Slack notification handle for alerts"
  type        = string
  default     = "@slack-t360-alerts"
}

variable "pagerduty_service" {
  description = "PagerDuty notification handle"
  type        = string
  default     = "@pagerduty-t360"
}

variable "slack_dba_channel" {
  description = "Slack notification handle for DBA team"
  type        = string
  default     = "@slack-t360-dba"
}

variable "pagerduty_dba_service" {
  description = "PagerDuty DBA on-call handle"
  type        = string
  default     = "@pagerduty-dba-oncall"
}

# ──────────────────────────────────────────────────────────────────────────────
# Synthetic Test Configuration
# ──────────────────────────────────────────────────────────────────────────────
variable "synthetic_locations" {
  description = "Locations for Datadog Synthetic tests"
  type        = list(string)
  default     = ["azure:eastus"]
}

variable "synthetic_check_interval" {
  description = "Synthetic test interval in seconds"
  type        = number
  default     = 300
}

# ──────────────────────────────────────────────────────────────────────────────
# Monitor Evaluation Windows
# ──────────────────────────────────────────────────────────────────────────────
variable "evaluation_windows" {
  description = "Evaluation window durations"
  type = object({
    short  = string  # For availability checks
    medium = string  # For performance checks
    long   = string  # For capacity checks
  })
  default = {
    short  = "last_5m"
    medium = "last_10m"
    long   = "last_15m"
  }
}
