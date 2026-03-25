################################################################################
# T360 Consolidated Datadog Dashboard
# Replaces AppDynamics LR-ELM-T360-consolidated dashboard
################################################################################

resource "datadog_dashboard" "t360_consolidated" {
  title       = "T360 Production - 13 Point Health Check"
  description = "Automated IPM checklist for cluster zuse1-d003-b066-aks-p1-t360-b. Replaces manual 3x/day AppDynamics check."
  layout_type = "ordered"

  # ── Header: Overall Health Summary ──────────────────────────────────────────
  widget {
    group_definition {
      title       = "T360 Overall Health"
      layout_type = "ordered"

      widget {
        note_definition {
          content          = "## T360 Production Health Dashboard\n**Cluster:** `zuse1-d003-b066-aks-p1-t360-b`\n**Subscription:** `D003-B066-ELM-Z-PRD-001`\n\nThis dashboard replaces the manual IPM 12-point checklist.\nAll checks run continuously (every 1-5 minutes)."
          background_color = "white"
          font_size        = "14"
          text_align       = "left"
          show_tick        = false
        }
      }

      widget {
        manage_status_definition {
          title           = "All T360 Monitor Status"
          display_format  = "countsAndList"
          color_preference = "text"
          hide_zero_counts = false
          query           = "tag:(app:t360)"
          sort             = "status,asc"
        }
      }
    }
  }

  # ── Item 1: Pods Availability ───────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Item 1: Pods Availability"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title = "Non-Running Pods"
          request {
            q          = "sum:kubernetes_state.pod.status_phase{kube_cluster_name:${var.aks_cluster_name},phase:pending} + sum:kubernetes_state.pod.status_phase{kube_cluster_name:${var.aks_cluster_name},phase:failed}"
            aggregator = "last"
          }
          precision = 0
        }
      }

      widget {
        timeseries_definition {
          title = "Pod Status Over Time"
          request {
            q            = "sum:kubernetes_state.pod.status_phase{kube_cluster_name:${var.aks_cluster_name}} by {phase}"
            display_type = "area"
          }
        }
      }
    }
  }

  # ── Items 2 & 3: FTP & SMTP Availability ───────────────────────────────────
  widget {
    group_definition {
      title       = "Items 2-3: FTP & SMTP Availability"
      layout_type = "ordered"

      widget {
        check_status_definition {
          title    = "FTP Server"
          check    = "synthetics.tcp"
          grouping = "cluster"
          tags     = ["check:item-2-ftp"]
        }
      }

      widget {
        check_status_definition {
          title    = "SMTP Server"
          check    = "synthetics.tcp"
          grouping = "cluster"
          tags     = ["check:item-3-smtp"]
        }
      }
    }
  }

  # ── Items 4-6: Database Health ──────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Items 4-6: Database Health"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title = "Lock Waits/sec"
          request {
            q          = "avg:sqlserver.stats.lock_waits_per_sec{app:t360}"
            aggregator = "last"
          }
          precision = 2
        }
      }

      widget {
        timeseries_definition {
          title = "Database CPU %"
          request {
            q            = "avg:azure.sql_servers_databases.cpu_percent{app:t360}"
            display_type = "line"
          }
        }
      }

      widget {
        query_value_definition {
          title = "Replication Lag (s)"
          request {
            q          = "max:custom.db.replication_lag_seconds{app:t360}"
            aggregator = "last"
          }
          precision = 1
        }
      }
    }
  }

  # ── Items 7 & 12: Disk Space ────────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Items 7 & 12: Disk Space"
      layout_type = "ordered"

      widget {
        toplist_definition {
          title = "Server Disk Usage (Item 7)"
          request {
            q = "max:system.disk.in_use{app:t360} by {host,device} * 100"
          }
        }
      }

      widget {
        toplist_definition {
          title = "AKS Node Disk Usage (Item 12)"
          request {
            q = "max:system.disk.in_use{kube_cluster_name:${var.aks_cluster_name}} by {host,device} * 100"
          }
        }
      }
    }
  }

  # ── Item 8: AKS Node Resources ─────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Item 8: AKS Node Availability"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title = "Node CPU Utilization %"
          request {
            q            = "avg:kubernetes.cpu.usage.total{kube_cluster_name:${var.aks_cluster_name}} by {host} / avg:kubernetes.cpu.capacity{kube_cluster_name:${var.aks_cluster_name}} by {host} * 100"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Node Memory Utilization %"
          request {
            q            = "avg:kubernetes.memory.usage{kube_cluster_name:${var.aks_cluster_name}} by {host} / avg:kubernetes.memory.capacity{kube_cluster_name:${var.aks_cluster_name}} by {host} * 100"
            display_type = "line"
          }
        }
      }
    }
  }

  # ── Item 9: VM Availability ─────────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Item 9: VM Availability"
      layout_type = "ordered"

      widget {
        check_status_definition {
          title    = "Agent Heartbeat"
          check    = "datadog.agent.up"
          grouping = "cluster"
          tags     = ["app:t360"]
        }
      }
    }
  }

  # ── Items 10 & 13: ITP Server Metrics ───────────────────────────────────────
  widget {
    group_definition {
      title       = "Items 10 & 13: ITP Server Health"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title = "MSMQ Queue Length (Item 10)"
          request {
            q          = "avg:custom.msmq.queue_length{app:t360}"
            aggregator = "last"
          }
          precision = 0
        }
      }

      widget {
        timeseries_definition {
          title = "Ephemeral Ports (Item 13)"
          request {
            q            = "avg:custom.itp.ephemeral_ports.available{app:t360}"
            display_type = "line"
          }
          request {
            q            = "avg:custom.itp.ephemeral_ports.bound{app:t360}"
            display_type = "line"
          }
          marker {
            value        = "y = ${var.thresholds.ephemeral_ports_critical}"
            display_type = "error dashed"
            label        = "Critical: ${var.thresholds.ephemeral_ports_critical}"
          }
        }
      }
    }
  }

  # ── Item 11: File Share ─────────────────────────────────────────────────────
  widget {
    group_definition {
      title       = "Item 11: File Share Size"
      layout_type = "ordered"

      widget {
        query_value_definition {
          title = "t360-prd-share Used Capacity"
          request {
            q          = "avg:azure.storage.file_services.file_share_usage{resource_group:${var.storage_resource_group}} / 1099511627776"
            aggregator = "last"
          }
          precision    = 2
          custom_unit  = "TB"
        }
      }

      widget {
        timeseries_definition {
          title = "File Share Growth Trend"
          request {
            q            = "avg:azure.storage.file_services.file_share_usage{resource_group:${var.storage_resource_group}}"
            display_type = "line"
          }
        }
      }
    }
  }

  tags = local.common_tags
}
