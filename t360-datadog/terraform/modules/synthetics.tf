################################################################################
# T360 Datadog Synthetic Tests - Items 2 & 3
################################################################################

# ══════════════════════════════════════════════════════════════════════════════
# ITEM 2: FTP Server Availability
# Original: Should always be 100%, create INCIDENT if less
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_synthetics_test" "t360_ftp_check" {
  name    = "[T360] Item 2 - FTP Server Availability"
  type    = "api"
  subtype = "tcp"
  status  = "live"

  message = <<-EOF
    ## T360 FTP Server Down

    {{#is_alert}}
    **CRITICAL:** FTP Server is unreachable!
    Host: `${var.ftp_server_host}:${var.ftp_server_port}`

    **Action Required:**
    1. Verify FTP service status on the server
    2. Check network connectivity and firewall rules
    3. Create an INCIDENT ticket immediately
    4. Escalate to infrastructure team

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_recovery}}
    RECOVERED: FTP Server is reachable again.
    {{/is_recovery}}
  EOF

  locations = var.synthetic_locations

  request_definition {
    host = var.ftp_server_host
    port = var.ftp_server_port
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "5000"
  }

  options_list {
    tick_every           = var.synthetic_check_interval
    min_failure_duration = 60
    min_location_failed  = 1

    retry {
      count    = 2
      interval = 30000  # 30 seconds
    }

    monitor_options {
      renotify_interval = 120
    }
  }

  tags = concat(local.common_tags, ["check:item-2-ftp", "priority:p1", "type:synthetic"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 3: SMTP Server Availability
# Original: Should always be 100%, create INCIDENT if less
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_synthetics_test" "t360_smtp_check" {
  name    = "[T360] Item 3 - SMTP Server Availability"
  type    = "api"
  subtype = "tcp"
  status  = "live"

  message = <<-EOF
    ## T360 SMTP Server Down

    {{#is_alert}}
    **CRITICAL:** SMTP Server is unreachable!
    Host: `${var.smtp_server_host}:${var.smtp_server_port}`

    **Action Required:**
    1. Verify SMTP service status on the server
    2. Check network connectivity and firewall rules
    3. Verify mail relay configuration
    4. Create an INCIDENT ticket immediately

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_recovery}}
    RECOVERED: SMTP Server is reachable again.
    {{/is_recovery}}
  EOF

  locations = var.synthetic_locations

  request_definition {
    host = var.smtp_server_host
    port = var.smtp_server_port
  }

  assertion {
    type     = "responseTime"
    operator = "lessThan"
    target   = "5000"
  }

  options_list {
    tick_every           = var.synthetic_check_interval
    min_failure_duration = 60
    min_location_failed  = 1

    retry {
      count    = 2
      interval = 30000
    }

    monitor_options {
      renotify_interval = 120
    }
  }

  tags = concat(local.common_tags, ["check:item-3-smtp", "priority:p1", "type:synthetic"])
}
