################################################################################
# T360 Datadog Monitoring - Outputs
################################################################################

output "monitor_ids" {
  description = "Map of all created monitor IDs"
  value = {
    pods_availability    = datadog_monitor.t360_pods_availability.id
    ftp_availability     = datadog_synthetics_test.t360_ftp_check.id
    smtp_availability    = datadog_synthetics_test.t360_smtp_check.id
    db_blocking          = datadog_monitor.t360_db_blocking.id
    db_performance       = datadog_monitor.t360_db_performance.id
    db_replication       = datadog_monitor.t360_db_replication.id
    disk_space           = datadog_monitor.t360_disk_space.id
    aks_node_cpu         = datadog_monitor.t360_aks_node_cpu.id
    aks_node_memory      = datadog_monitor.t360_aks_node_memory.id
    vm_availability      = datadog_monitor.t360_vm_availability.id
    msmq                 = datadog_monitor.t360_msmq.id
    file_share           = datadog_monitor.t360_file_share.id
    aks_node_disk        = datadog_monitor.t360_aks_node_disk.id
    ephemeral_ports      = datadog_monitor.t360_ephemeral_ports.id
  }
}

output "dashboard_url" {
  description = "URL to the consolidated T360 dashboard"
  value       = datadog_dashboard.t360_consolidated.url
}

output "synthetic_test_ids" {
  description = "Synthetic test public IDs"
  value = {
    ftp  = datadog_synthetics_test.t360_ftp_check.id
    smtp = datadog_synthetics_test.t360_smtp_check.id
  }
}
