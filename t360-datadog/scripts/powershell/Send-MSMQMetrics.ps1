<#
.SYNOPSIS
    T360 ITP MSMQ Monitor - Sends queue metrics to Datadog via DogStatsD.

.DESCRIPTION
    Monitors MSMQ queue lengths for T360 ITP services and sends metrics
    to Datadog. Replaces Item 10 manual check from the 12-point checklist.
    Queue length should always be zero.

.PARAMETER DogStatsDHost
    Hostname or IP of the DogStatsD server (default: 127.0.0.1)

.PARAMETER DogStatsDPort
    Port for DogStatsD (default: 8125)

.PARAMETER QueueFilter
    Wildcard filter for queue names (default: *t360*)

.NOTES
    Deploy to: zuse1p1t360itp1.wkrainier.com
    Schedule:  Every 1 minute via Task Scheduler
    Author:    T360 Operations Team
    Version:   1.0.0
#>

[CmdletBinding()]
param(
    [string]$DogStatsDHost = "127.0.0.1",
    [int]$DogStatsDPort = 8125,
    [string]$QueueFilter = "*t360*"
)

$ErrorActionPreference = "Stop"
$LogPath = "C:\Logs\Datadog\msmq-metrics.log"
$Hostname = $env:COMPUTERNAME.ToLower()

# Ensure log directory exists
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$Timestamp] [$Level] $Message"
}

function Send-DogStatsD {
    param(
        [string]$MetricName,
        [double]$Value,
        [string]$Type = "g",
        [string[]]$Tags = @()
    )

    $TagString = ""
    if ($Tags.Count -gt 0) {
        $TagString = "|#" + ($Tags -join ",")
    }

    $Payload = "${MetricName}:${Value}|${Type}${TagString}"

    try {
        $UdpClient = New-Object System.Net.Sockets.UdpClient
        $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Payload)
        $UdpClient.Send($Bytes, $Bytes.Length, $DogStatsDHost, $DogStatsDPort) | Out-Null
        $UdpClient.Close()
    }
    catch {
        Write-Log "Failed to send DogStatsD metric: $Payload - $_" -Level "ERROR"
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────
try {
    Write-Log "=== Starting MSMQ check ==="

    # Check if MSMQ is installed
    $MsmqService = Get-Service -Name "MSMQ" -ErrorAction SilentlyContinue
    if ($null -eq $MsmqService) {
        Write-Log "MSMQ service not found on this server" -Level "ERROR"
        Send-DogStatsD -MetricName "custom.msmq.service_available" -Value 0 -Tags @("app:t360", "host:$Hostname")
        exit 1
    }

    # Send MSMQ service status
    $ServiceUp = if ($MsmqService.Status -eq "Running") { 1 } else { 0 }
    Send-DogStatsD -MetricName "custom.msmq.service_available" -Value $ServiceUp -Tags @("app:t360", "host:$Hostname")

    if ($MsmqService.Status -ne "Running") {
        Write-Log "MSMQ service is not running: $($MsmqService.Status)" -Level "WARN"
        exit 1
    }

    # Get all MSMQ queues
    $AllQueues = Get-MsmqQueue -ErrorAction SilentlyContinue

    if ($null -eq $AllQueues -or $AllQueues.Count -eq 0) {
        Write-Log "No MSMQ queues found"
        Send-DogStatsD -MetricName "custom.msmq.queue_length" -Value 0 -Tags @(
            "app:t360", "host:$Hostname", "service:itp", "queue:all"
        )
        Send-DogStatsD -MetricName "custom.msmq.queue_count" -Value 0 -Tags @(
            "app:t360", "host:$Hostname"
        )
        exit 0
    }

    # Filter for T360-related queues
    $T360Queues = $AllQueues | Where-Object { $_.QueueName -like $QueueFilter }
    $TotalMessages = 0

    Write-Log "Found $($AllQueues.Count) total queues, $(@($T360Queues).Count) matching filter '$QueueFilter'"

    # Send per-queue metrics
    foreach ($Queue in $T360Queues) {
        $QueueName = $Queue.QueueName -replace '[^a-zA-Z0-9_-]', '_'
        $MessageCount = $Queue.MessageCount

        $TotalMessages += $MessageCount

        $Tags = @(
            "app:t360",
            "host:$Hostname",
            "service:itp",
            "queue:$QueueName"
        )

        Send-DogStatsD -MetricName "custom.msmq.queue_length" -Value $MessageCount -Tags $Tags
        Send-DogStatsD -MetricName "custom.msmq.queue_bytes" -Value $Queue.BytesInQueue -Tags $Tags

        if ($MessageCount -gt 0) {
            Write-Log "Queue '$($Queue.QueueName)' has $MessageCount messages" -Level "WARN"
        }
    }

    # Send total metrics
    $TotalTags = @("app:t360", "host:$Hostname", "service:itp", "queue:all")
    Send-DogStatsD -MetricName "custom.msmq.total_messages" -Value $TotalMessages -Tags $TotalTags
    Send-DogStatsD -MetricName "custom.msmq.queue_count" -Value @($T360Queues).Count -Tags @("app:t360", "host:$Hostname")

    # Also send aggregate for all queues (for overall dashboard)
    $AllMessageCount = ($AllQueues | Measure-Object -Property MessageCount -Sum).Sum
    Send-DogStatsD -MetricName "custom.msmq.queue_length" -Value $AllMessageCount -Tags @(
        "app:t360", "host:$Hostname", "service:itp"
    )

    Write-Log "Total T360 messages across all queues: $TotalMessages"
    Write-Log "=== MSMQ check completed ==="
}
catch {
    Write-Log "MSMQ check failed: $_" -Level "ERROR"
    exit 1
}
