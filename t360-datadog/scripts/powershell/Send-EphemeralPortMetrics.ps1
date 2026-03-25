<#
.SYNOPSIS
    T360 ITP Ephemeral Ports Monitor - Sends port metrics to Datadog via DogStatsD.

.DESCRIPTION
    This script checks ephemeral (dynamic) port usage on the ITP server
    and sends available/bound port counts to Datadog via DogStatsD UDP.
    Replaces Item 13 manual check from the T360 12-point checklist.

    Threshold: If available ports <= 4000, create Sev-3 INCIDENT and
    restart T360 Network Processing Service.

.PARAMETER DogStatsDHost
    Hostname or IP of the DogStatsD server (default: 127.0.0.1)

.PARAMETER DogStatsDPort
    Port for DogStatsD (default: 8125)

.PARAMETER ServiceName
    Name of the T360 Network Processing Service to monitor/restart

.PARAMETER AutoRestart
    If true, automatically restart the service when ports drop below threshold

.PARAMETER Threshold
    Port count threshold below which an alert is triggered (default: 4000)

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
    [string]$ServiceName = "T360 Network Processing Service",
    [switch]$AutoRestart,
    [int]$Threshold = 4000
)

# ──────────────────────────────────────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────────────────────────────────────
$ErrorActionPreference = "Stop"
$LogPath = "C:\Logs\Datadog\ephemeral-ports.log"
$Hostname = $env:COMPUTERNAME.ToLower()

# Ensure log directory exists
$LogDir = Split-Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# ──────────────────────────────────────────────────────────────────────────────
# Functions
# ──────────────────────────────────────────────────────────────────────────────
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Add-Content -Path $LogPath -Value $LogEntry
    if ($Level -eq "ERROR") { Write-Error $Message }
    elseif ($Level -eq "WARN") { Write-Warning $Message }
    else { Write-Host $LogEntry }
}

function Send-DogStatsD {
    param(
        [string]$MetricName,
        [double]$Value,
        [string]$Type = "g",     # g=gauge, c=count, h=histogram
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
        Write-Log "Sent metric: $Payload"
    }
    catch {
        Write-Log "Failed to send metric: $Payload - Error: $_" -Level "ERROR"
    }
}

function Get-EphemeralPortStats {
    <#
    .DESCRIPTION
        Gets the current ephemeral port usage using netstat.
        Dynamic port range is typically 49152-65535 (16384 ports).
    #>

    # Get the dynamic port range
    try {
        $DynamicPortRange = netsh int ipv4 show dynamicport tcp
        $StartPort = 0
        $NumPorts = 0

        foreach ($Line in $DynamicPortRange) {
            if ($Line -match "Start Port\s*:\s*(\d+)") {
                $StartPort = [int]$Matches[1]
            }
            if ($Line -match "Number of Ports\s*:\s*(\d+)") {
                $NumPorts = [int]$Matches[1]
            }
        }

        if ($NumPorts -eq 0) {
            # Default Windows dynamic port range
            $StartPort = 49152
            $NumPorts = 16384
        }

        Write-Log "Dynamic port range: $StartPort - $($StartPort + $NumPorts - 1) ($NumPorts total)"
    }
    catch {
        Write-Log "Could not determine dynamic port range, using defaults" -Level "WARN"
        $StartPort = 49152
        $NumPorts = 16384
    }

    # Count TCP connections in the dynamic port range
    try {
        $TcpConnections = Get-NetTCPConnection -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -ge $StartPort -and $_.LocalPort -lt ($StartPort + $NumPorts) }

        $BoundPorts = ($TcpConnections | Measure-Object).Count
        $AvailablePorts = $NumPorts - $BoundPorts

        # Breakdown by state
        $EstablishedCount = ($TcpConnections | Where-Object { $_.State -eq "Established" } | Measure-Object).Count
        $TimeWaitCount = ($TcpConnections | Where-Object { $_.State -eq "TimeWait" } | Measure-Object).Count
        $CloseWaitCount = ($TcpConnections | Where-Object { $_.State -eq "CloseWait" } | Measure-Object).Count

        return @{
            TotalPorts    = $NumPorts
            BoundPorts    = $BoundPorts
            Available     = $AvailablePorts
            Established   = $EstablishedCount
            TimeWait      = $TimeWaitCount
            CloseWait     = $CloseWaitCount
            StartPort     = $StartPort
        }
    }
    catch {
        Write-Log "Error getting TCP connections: $_" -Level "ERROR"
        # Fallback to netstat
        $NetstatOutput = netstat -an | Select-String "TCP" |
            Where-Object { $_ -match ":(\d+)\s" -and [int]$Matches[1] -ge $StartPort }
        $BoundPorts = ($NetstatOutput | Measure-Object).Count
        $AvailablePorts = $NumPorts - $BoundPorts

        return @{
            TotalPorts  = $NumPorts
            BoundPorts  = $BoundPorts
            Available   = $AvailablePorts
            Established = 0
            TimeWait    = 0
            CloseWait   = 0
            StartPort   = $StartPort
        }
    }
}

function Restart-T360Service {
    param([string]$Name)

    Write-Log "Attempting to restart service: $Name" -Level "WARN"

    try {
        $Service = Get-Service -DisplayName $Name -ErrorAction SilentlyContinue
        if ($null -eq $Service) {
            $Service = Get-Service -Name $Name -ErrorAction SilentlyContinue
        }

        if ($null -eq $Service) {
            Write-Log "Service '$Name' not found!" -Level "ERROR"
            return $false
        }

        Write-Log "Service status before restart: $($Service.Status)"

        Restart-Service -InputObject $Service -Force -ErrorAction Stop
        Start-Sleep -Seconds 10

        $Service.Refresh()
        Write-Log "Service status after restart: $($Service.Status)"

        if ($Service.Status -eq "Running") {
            Write-Log "Service restarted successfully"

            # Send event to Datadog
            Send-DogStatsD -MetricName "custom.itp.service_restart" -Value 1 -Type "c" -Tags @(
                "app:t360",
                "host:$Hostname",
                "service:t360-network-processing",
                "reason:port-exhaustion"
            )
            return $true
        }
        else {
            Write-Log "Service did not start properly after restart" -Level "ERROR"
            return $false
        }
    }
    catch {
        Write-Log "Failed to restart service: $_" -Level "ERROR"
        return $false
    }
}

# ──────────────────────────────────────────────────────────────────────────────
# Main Execution
# ──────────────────────────────────────────────────────────────────────────────
try {
    Write-Log "=== Starting ephemeral port check ==="

    # Get port statistics
    $PortStats = Get-EphemeralPortStats

    Write-Log "Port Stats - Total: $($PortStats.TotalPorts) | Bound: $($PortStats.BoundPorts) | Available: $($PortStats.Available)"
    Write-Log "  Established: $($PortStats.Established) | TimeWait: $($PortStats.TimeWait) | CloseWait: $($PortStats.CloseWait)"

    # Common tags
    $CommonTags = @(
        "app:t360",
        "host:$Hostname",
        "service:t360-network-processing",
        "env:production"
    )

    # Send metrics to Datadog
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.available" -Value $PortStats.Available -Tags $CommonTags
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.bound" -Value $PortStats.BoundPorts -Tags $CommonTags
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.total" -Value $PortStats.TotalPorts -Tags $CommonTags
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.established" -Value $PortStats.Established -Tags $CommonTags
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.timewait" -Value $PortStats.TimeWait -Tags $CommonTags
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.closewait" -Value $PortStats.CloseWait -Tags $CommonTags

    # Utilization percentage
    $UtilizationPct = [math]::Round(($PortStats.BoundPorts / $PortStats.TotalPorts) * 100, 2)
    Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.utilization_pct" -Value $UtilizationPct -Tags $CommonTags

    # Check threshold
    if ($PortStats.Available -le $Threshold) {
        Write-Log "PORT EXHAUSTION WARNING: Available ports ($($PortStats.Available)) <= threshold ($Threshold)" -Level "WARN"

        # Send critical event
        Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.threshold_breach" -Value 1 -Type "c" -Tags ($CommonTags + @("severity:sev3"))

        if ($AutoRestart) {
            Write-Log "AutoRestart enabled. Restarting $ServiceName..."
            $RestartResult = Restart-T360Service -Name $ServiceName

            if ($RestartResult) {
                # Re-check ports after restart
                Start-Sleep -Seconds 15
                $PostRestartStats = Get-EphemeralPortStats
                Write-Log "Post-restart available ports: $($PostRestartStats.Available)"
                Send-DogStatsD -MetricName "custom.itp.ephemeral_ports.available" -Value $PostRestartStats.Available -Tags $CommonTags
            }
        }
        else {
            Write-Log "AutoRestart disabled. Manual intervention required." -Level "WARN"
        }
    }
    else {
        Write-Log "Port availability OK: $($PortStats.Available) available (threshold: $Threshold)"
    }

    Write-Log "=== Ephemeral port check completed ==="
}
catch {
    Write-Log "Script execution failed: $_" -Level "ERROR"
    exit 1
}
