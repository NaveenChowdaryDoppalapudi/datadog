################################################################################
# T360 Datadog Monitors - All 13 Checkpoints
# Cluster: zuse1-d003-b066-aks-p1-t360-b
################################################################################

# ══════════════════════════════════════════════════════════════════════════════
# ITEM 1: Pods Availability
# Original: Check in Lens, should always be zero unavailable
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_pods_availability" {
  name    = "[T360] Item 1 - Pods Availability"
  type    = "query alert"
  message = <<-EOF
    ## T360 Pod Availability Alert

    {{#is_alert}}
    **CRITICAL:** Pods are not running in cluster `${var.aks_cluster_name}`.

    **Current value:** {{value}} pods in non-running state
    **Namespace:** {{kube_namespace.name}}
    **Pod:** {{pod_name.name}}

    **Action Required:**
    1. Check pod status: `kubectl get pods -n {{kube_namespace.name}} --field-selector=status.phase!=Running`
    2. Check pod events: `kubectl describe pod {{pod_name.name}} -n {{kube_namespace.name}}`
    3. Check node resources: `kubectl top nodes`

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    **WARNING:** Pod restarts detected in cluster `${var.aks_cluster_name}`.
    Pod: {{pod_name.name}} | Namespace: {{kube_namespace.name}}
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    **RECOVERED:** All T360 pods are running normally.
    {{/is_recovery}}
  EOF

  query = "max(${var.evaluation_windows.short}):sum:kubernetes_state.pod.status_phase{kube_cluster_name:${var.aks_cluster_name},phase:pending} by {kube_namespace,pod_name} + sum:kubernetes_state.pod.status_phase{kube_cluster_name:${var.aks_cluster_name},phase:failed} by {kube_namespace,pod_name} > ${var.thresholds.pod_min_running}"

  monitor_thresholds {
    critical = var.thresholds.pod_min_running
    warning  = 0
  }

  notify_no_data    = true
  no_data_timeframe = 10
  renotify_interval = 15
  escalation_message = "Pod availability issue persisting for T360. Escalating. ${var.pagerduty_service}"

  tags = concat(local.common_tags, ["check:item-1-pods-availability", "priority:p1"])
}

# Pod restart monitor (complementary to availability)
resource "datadog_monitor" "t360_pod_restarts" {
  name    = "[T360] Item 1b - Pod CrashLoopBackOff Detection"
  type    = "query alert"
  message = <<-EOF
    {{#is_alert}}
    **ALERT:** Pod restart rate is high — possible CrashLoopBackOff.
    Pod: {{pod_name.name}} | Restarts: {{value}}
    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}
    {{#is_recovery}}
    **RECOVERED:** Pod restart rate returned to normal.
    {{/is_recovery}}
  EOF

  query = "change(avg(${var.evaluation_windows.medium}),${var.evaluation_windows.medium}):sum:kubernetes_state.container.restarts{kube_cluster_name:${var.aks_cluster_name}} by {pod_name,kube_namespace} > 5"

  monitor_thresholds {
    critical = 5
    warning  = 3
  }

  tags = concat(local.common_tags, ["check:item-1b-pod-restarts", "priority:p2"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 4: Database Blocking
# Original: Contact DBA team for data
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_db_blocking" {
  name    = "[T360] Item 4 - Database Blocking Detected"
  type    = "query alert"
  message = <<-EOF
    ## T360 Database Blocking Alert

    {{#is_alert}}
    **CRITICAL:** Database blocking detected.
    **Blocked sessions:** {{value}}

    **Action Required:**
    1. Check blocking queries in Datadog DBM: Live Queries > Waiting Queries
    2. Contact DBA on-call if blocking persists beyond 5 minutes
    3. Consider killing blocking session if identified

    ${var.slack_dba_channel} ${var.dba_pagerduty}
    {{/is_alert}}

    {{#is_warning}}
    **WARNING:** Elevated blocking sessions detected: {{value}}
    ${var.slack_dba_channel}
    {{/is_warning}}

    {{#is_recovery}}
    **RECOVERED:** Database blocking has cleared.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):avg:sqlserver.stats.lock_waits_per_sec{app:t360} > ${var.thresholds.db_blocking_critical}"

  monitor_thresholds {
    critical = var.thresholds.db_blocking_critical
    warning  = var.thresholds.db_blocking_warning
  }

  notify_no_data    = false
  renotify_interval = 10

  tags = concat(local.common_tags, ["check:item-4-db-blocking", "priority:p1", "team:dba"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 5: Database Performance
# Original: Contact DBA team for data
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_db_performance" {
  name    = "[T360] Item 5 - Database Performance Degradation"
  type    = "query alert"
  message = <<-EOF
    ## T360 Database Performance Alert

    {{#is_alert}}
    **CRITICAL:** Database CPU utilization at {{value}}%.

    **Action Required:**
    1. Check Datadog DBM for top queries by CPU
    2. Review query execution plans for regressions
    3. Contact DBA on-call for performance tuning

    ${var.slack_dba_channel} ${var.dba_pagerduty}
    {{/is_alert}}

    {{#is_warning}}
    **WARNING:** Database CPU elevated at {{value}}%.
    ${var.slack_dba_channel}
    {{/is_warning}}

    {{#is_recovery}}
    **RECOVERED:** Database performance returned to normal.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.medium}):avg:azure.sql_servers_databases.cpu_percent{app:t360} > ${var.thresholds.db_cpu_critical}"

  monitor_thresholds {
    critical = var.thresholds.db_cpu_critical
    warning  = var.thresholds.db_cpu_warning
  }

  tags = concat(local.common_tags, ["check:item-5-db-performance", "priority:p1", "team:dba"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 6: Database Replication
# Original: Contact DBA team for data
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_db_replication" {
  name    = "[T360] Item 6 - Database Replication Lag"
  type    = "query alert"
  message = <<-EOF
    ## T360 Replication Lag Alert

    {{#is_alert}}
    **CRITICAL:** Replication lag is {{value}} seconds.

    **Action Required:**
    1. Check replica health in Azure Portal or Datadog DBM
    2. Verify network connectivity between primary and replica
    3. Contact DBA on-call for intervention

    ${var.slack_dba_channel} ${var.dba_pagerduty}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: Replication lag increasing — {{value}} seconds.
    ${var.slack_dba_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: Replication lag is back within acceptable range.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):max:custom.db.replication_lag_seconds{app:t360} > ${var.thresholds.replication_lag_critical_s}"

  monitor_thresholds {
    critical = var.thresholds.replication_lag_critical_s
    warning  = var.thresholds.replication_lag_warning_s
  }

  notify_no_data    = true
  no_data_timeframe = 20

  tags = concat(local.common_tags, ["check:item-6-replication", "priority:p1", "team:dba"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 7: Disk Space
# Original: Should always be below 100%
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_disk_space" {
  name    = "[T360] Item 7 - Disk Space Usage"
  type    = "query alert"
  message = <<-EOF
    ## T360 Disk Space Alert

    {{#is_alert}}
    **CRITICAL:** Disk usage on `{{host.name}}` device `{{device.name}}` is at {{value}}%.

    **Action Required:**
    1. SSH to {{host.name}} and check disk usage: `df -h`
    2. Identify large files: `du -sh /* | sort -rh | head -20`
    3. Clean up logs, temp files, or old deployments
    4. Consider expanding disk if recurring

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: Disk usage on `{{host.name}}` reaching {{value}}%.
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: Disk usage on `{{host.name}}` is back to normal.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):max:system.disk.in_use{app:t360} by {host,device} * 100 > ${var.thresholds.disk_critical_pct}"

  monitor_thresholds {
    critical = var.thresholds.disk_critical_pct
    warning  = var.thresholds.disk_warning_pct
  }

  tags = concat(local.common_tags, ["check:item-7-disk-space", "priority:p2"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 8: AKS Node Availability (CPU + Memory)
# Original: Check Memory and CPU in Grafana
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_aks_node_cpu" {
  name    = "[T360] Item 8a - AKS Node CPU Utilization"
  type    = "query alert"
  message = <<-EOF
    ## T360 AKS Node CPU Alert

    {{#is_alert}}
    **CRITICAL:** AKS Node `{{host.name}}` CPU at {{value}}%.
    Cluster: `${var.aks_cluster_name}`

    **Action Required:**
    1. Check node workloads: `kubectl top pods --all-namespaces --sort-by=cpu`
    2. Review pod resource requests/limits
    3. Consider scaling nodepool or evicting non-critical pods

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: AKS Node `{{host.name}}` CPU at {{value}}%.
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: AKS Node `{{host.name}}` CPU returned to normal.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.medium}):avg:kubernetes.cpu.usage.total{kube_cluster_name:${var.aks_cluster_name}} by {host} / avg:kubernetes.cpu.capacity{kube_cluster_name:${var.aks_cluster_name}} by {host} * 100 > ${var.thresholds.aks_node_cpu_critical}"

  monitor_thresholds {
    critical = var.thresholds.aks_node_cpu_critical
    warning  = var.thresholds.aks_node_cpu_warning
  }

  tags = concat(local.common_tags, ["check:item-8a-aks-cpu", "priority:p1"])
}

resource "datadog_monitor" "t360_aks_node_memory" {
  name    = "[T360] Item 8b - AKS Node Memory Utilization"
  type    = "query alert"
  message = <<-EOF
    ## T360 AKS Node Memory Alert

    {{#is_alert}}
    **CRITICAL:** AKS Node `{{host.name}}` Memory at {{value}}%.
    Cluster: `${var.aks_cluster_name}`

    **Action Required:**
    1. Check memory consumers: `kubectl top pods --all-namespaces --sort-by=memory`
    2. Look for memory leaks in application pods
    3. Consider scaling nodepool

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: AKS Node `{{host.name}}` Memory at {{value}}%.
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: AKS Node `{{host.name}}` Memory returned to normal.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.medium}):avg:kubernetes.memory.usage{kube_cluster_name:${var.aks_cluster_name}} by {host} / avg:kubernetes.memory.capacity{kube_cluster_name:${var.aks_cluster_name}} by {host} * 100 > ${var.thresholds.aks_node_memory_critical}"

  monitor_thresholds {
    critical = var.thresholds.aks_node_memory_critical
    warning  = var.thresholds.aks_node_memory_warning
  }

  tags = concat(local.common_tags, ["check:item-8b-aks-memory", "priority:p1"])
}

# AKS Node Status (NotReady detection)
resource "datadog_monitor" "t360_aks_node_status" {
  name    = "[T360] Item 8c - AKS Node NotReady"
  type    = "service check"
  message = <<-EOF
    {{#is_alert}}
    **CRITICAL:** AKS Node `{{host.name}}` is NotReady!
    Cluster: `${var.aks_cluster_name}`

    Run: `kubectl get nodes` and `kubectl describe node {{host.name}}`
    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}
    {{#is_recovery}}
    RECOVERED: AKS Node `{{host.name}}` is Ready.
    {{/is_recovery}}
  EOF

  query = "\"kubernetes_state.node.ready\".over(\"kube_cluster_name:${var.aks_cluster_name}\").by(\"host\").last(3).count_by_status()"

  monitor_thresholds {
    critical = 3
    warning  = 1
    ok       = 1
  }

  tags = concat(local.common_tags, ["check:item-8c-aks-node-status", "priority:p1"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 9: VM Availability
# Original: Should always be 100%
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_vm_availability" {
  name    = "[T360] Item 9 - VM Availability (Agent Heartbeat)"
  type    = "service check"
  message = <<-EOF
    ## T360 VM Down Alert

    {{#is_alert}}
    **CRITICAL:** VM `{{host.name}}` is not reporting to Datadog!

    **Action Required:**
    1. Check VM status in Azure Portal
    2. Attempt RDP/SSH to the host
    3. If VM is deallocated, start it
    4. If VM is running but agent is down, restart the Datadog Agent service

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_recovery}}
    RECOVERED: VM `{{host.name}}` is reporting again.
    {{/is_recovery}}
  EOF

  query = "\"datadog.agent.up\".over(\"app:t360\").by(\"host\").last(2).count_by_status()"

  monitor_thresholds {
    critical = 1
    warning  = 1
    ok       = 1
  }

  notify_no_data    = true
  no_data_timeframe = 5

  tags = concat(local.common_tags, ["check:item-9-vm-availability", "priority:p1"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 10: ITP MSMQ Availability
# Original: Should always be zero
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_msmq" {
  name    = "[T360] Item 10 - ITP MSMQ Queue Length"
  type    = "query alert"
  message = <<-EOF
    ## T360 MSMQ Alert

    {{#is_alert}}
    **CRITICAL:** MSMQ queue length is {{value}} (expected: 0).
    Host: `${var.itp_server_hostname}`

    **Action Required:**
    1. RDP to ${var.itp_server_hostname}
    2. Open Computer Management > Services and Applications > Message Queuing
    3. Check for stuck messages in the queue
    4. Verify T360 Network Processing Service is running

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: MSMQ queue has {{value}} messages pending.
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: MSMQ queue is back to zero.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):avg:custom.msmq.queue_length{app:t360,host:${replace(var.itp_server_hostname, ".", "_")}} > ${var.thresholds.msmq_critical}"

  monitor_thresholds {
    critical = var.thresholds.msmq_critical
    warning  = var.thresholds.msmq_warning
  }

  notify_no_data    = true
  no_data_timeframe = 15

  tags = concat(local.common_tags, ["check:item-10-msmq", "priority:p2"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 11: File Share Size
# Original: Check Azure portal for used capacity
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_file_share" {
  name    = "[T360] Item 11 - File Share Capacity (t360-prd-share)"
  type    = "query alert"
  message = <<-EOF
    ## T360 File Share Capacity Alert

    {{#is_alert}}
    **CRITICAL:** File share `${var.file_share_name}` capacity at {{value}} bytes.
    Approaching storage quota.

    **Action Required:**
    1. Review file share in Azure Portal
    2. Identify large/stale files for cleanup
    3. Consider increasing share quota if needed

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: File share `${var.file_share_name}` at {{value}} bytes.
    Current threshold: 3.5 TB warning / 4.0 TB critical
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: File share capacity is within limits.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.long}):avg:azure.storage.file_services.file_share_usage{resource_group:${var.storage_resource_group},account_name:${var.storage_account_name}} > ${var.thresholds.file_share_critical_bytes}"

  monitor_thresholds {
    critical = var.thresholds.file_share_critical_bytes
    warning  = var.thresholds.file_share_warning_bytes
  }

  tags = concat(local.common_tags, ["check:item-11-file-share", "priority:p2"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 12: AKS Node Disk Space
# Original: Run az CLI, cleanup if > 75%
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_aks_node_disk" {
  name    = "[T360] Item 12 - AKS Node Disk Space"
  type    = "query alert"
  message = <<-EOF
    ## T360 AKS Node Disk Alert

    {{#is_alert}}
    **CRITICAL:** AKS Node `{{host.name}}` disk at {{value}}%.

    **Action Required (per SOP):**
    1. Clean up cached container images on the node
    2. Run image prune: `docker system prune -a --filter "until=72h"`
    3. Or follow SOP: https://confluence.wolterskluwer.io/display/GRCELMNFR/T360+-+SOPs

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: AKS Node `{{host.name}}` disk at {{value}}% (threshold: 75%).
    Review cached images.
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: AKS Node `{{host.name}}` disk usage normalized.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):max:system.disk.in_use{kube_cluster_name:${var.aks_cluster_name}} by {host,device} * 100 > ${var.thresholds.aks_disk_critical_pct}"

  monitor_thresholds {
    critical = var.thresholds.aks_disk_critical_pct
    warning  = var.thresholds.aks_disk_warning_pct
  }

  tags = concat(local.common_tags, ["check:item-12-aks-disk", "priority:p1"])
}


# ══════════════════════════════════════════════════════════════════════════════
# ITEM 13: ITP Ephemeral Ports
# Original: Login to server, run PowerShell, check available ports
# ══════════════════════════════════════════════════════════════════════════════
resource "datadog_monitor" "t360_ephemeral_ports" {
  name    = "[T360] Item 13 - ITP Ephemeral Ports"
  type    = "query alert"
  message = <<-EOF
    ## T360 Ephemeral Port Exhaustion Alert

    {{#is_alert}}
    **SEV-3:** Ephemeral ports available: {{value}} on `${var.itp_server_hostname}`.

    Ports are at or below ${var.thresholds.ephemeral_ports_critical}.

    **Action Required (per SOP):**
    1. Create Sev-3 INCIDENT ticket
    2. RDP to ${var.itp_server_hostname}
    3. Restart "T360 Network Processing Service"
    4. Verify ports recover after restart

    SOP: https://confluence.wolterskluwer.io/spaces/GRCELMNFR/pages/850418240

    ${var.slack_alert_channel} ${var.pagerduty_service}
    {{/is_alert}}

    {{#is_warning}}
    WARNING: Ephemeral ports dropping on `${var.itp_server_hostname}`.
    Available: {{value}} (warning threshold: ${var.thresholds.ephemeral_ports_warning})
    ${var.slack_alert_channel}
    {{/is_warning}}

    {{#is_recovery}}
    RECOVERED: Ephemeral port availability is back to healthy levels.
    {{/is_recovery}}
  EOF

  query = "avg(${var.evaluation_windows.short}):min:custom.itp.ephemeral_ports.available{host:${replace(var.itp_server_hostname, ".", "_")}} < ${var.thresholds.ephemeral_ports_critical}"

  monitor_thresholds {
    critical = var.thresholds.ephemeral_ports_critical
    warning  = var.thresholds.ephemeral_ports_warning
  }

  notify_no_data    = true
  no_data_timeframe = 15

  tags = concat(local.common_tags, ["check:item-13-ephemeral-ports", "priority:p1"])
}
