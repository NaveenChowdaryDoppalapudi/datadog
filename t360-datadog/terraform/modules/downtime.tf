################################################################################
# T360 Scheduled Maintenance / Downtime Windows
################################################################################

# Example: Weekly maintenance window (adjust as needed)
resource "datadog_downtime_schedule" "t360_maintenance" {
  scope = "app:t360"

  display_timezone = "America/Chicago"

  recurring_schedule {
    timezone = "America/Chicago"

    recurrence {
      duration = "2h"
      rrule    = "FREQ=WEEKLY;BYDAY=SU;BYHOUR=2;BYMINUTE=0"
      start    = "2025-01-01T02:00:00"
    }
  }

  monitor_identifier {
    monitor_tags = ["app:t360"]
  }

  message = "Scheduled weekly maintenance window for T360. All monitors muted during this period."
}
