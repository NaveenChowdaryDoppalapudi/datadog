################################################################################
# T360 Service Level Objectives
################################################################################

resource "datadog_service_level_objective" "t360_pod_availability" {
  name        = "T360 Pod Availability SLO"
  type        = "monitor"
  description = "99.9% of the time, all T360 pods should be in Running state"

  monitor_ids = [datadog_monitor.t360_pods_availability.id]

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  thresholds {
    timeframe = "7d"
    target    = 99.9
    warning   = 99.95
  }

  tags = concat(local.common_tags, ["slo:pod-availability"])
}

resource "datadog_service_level_objective" "t360_ftp_availability" {
  name        = "T360 FTP Server Availability SLO"
  type        = "monitor"
  description = "FTP server must be 100% available (target 99.95%)"

  monitor_ids = [datadog_synthetics_test.t360_ftp_check.monitor_id]

  thresholds {
    timeframe = "30d"
    target    = 99.95
    warning   = 99.99
  }

  tags = concat(local.common_tags, ["slo:ftp-availability"])
}

resource "datadog_service_level_objective" "t360_smtp_availability" {
  name        = "T360 SMTP Server Availability SLO"
  type        = "monitor"
  description = "SMTP server must be 100% available (target 99.95%)"

  monitor_ids = [datadog_synthetics_test.t360_smtp_check.monitor_id]

  thresholds {
    timeframe = "30d"
    target    = 99.95
    warning   = 99.99
  }

  tags = concat(local.common_tags, ["slo:smtp-availability"])
}

resource "datadog_service_level_objective" "t360_vm_availability" {
  name        = "T360 VM Availability SLO"
  type        = "monitor"
  description = "All T360 VMs should be available 99.9% of the time"

  monitor_ids = [datadog_monitor.t360_vm_availability.id]

  thresholds {
    timeframe = "30d"
    target    = 99.9
    warning   = 99.95
  }

  tags = concat(local.common_tags, ["slo:vm-availability"])
}
