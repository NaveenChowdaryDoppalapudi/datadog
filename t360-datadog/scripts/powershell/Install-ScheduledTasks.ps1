<#
.SYNOPSIS
    Installs Windows Scheduled Tasks for T360 Datadog custom metric collection.

.DESCRIPTION
    Creates scheduled tasks that run every 1 minute to collect and send
    MSMQ queue metrics (Item 10) and Ephemeral Port metrics (Item 13)
    to Datadog via DogStatsD.

    Must be run as Administrator on zuse1p1t360itp1.wkrainier.com.

.PARAMETER ScriptPath
    Path where the monitoring scripts are deployed (default: C:\Scripts\Datadog)

.PARAMETER Uninstall
    If specified, removes the scheduled tasks instead of creating them

.NOTES
    Run as: Administrator
    Server: zuse1p1t360itp1.wkrainier.com
#>

[CmdletBinding()]
param(
    [string]$ScriptPath = "C:\Scripts\Datadog",
    [switch]$Uninstall
)

$ErrorActionPreference = "Stop"

# ──────────────────────────────────────────────────────────────────────────────
# Validate prerequisites
# ──────────────────────────────────────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator."
    exit 1
}

# ──────────────────────────────────────────────────────────────────────────────
# Task definitions
# ──────────────────────────────────────────────────────────────────────────────
$Tasks = @(
    @{
        Name        = "T360-Datadog-MSMQ-Metrics"
        Description = "Sends MSMQ queue metrics to Datadog every minute (T360 Item 10)"
        Script      = "Send-MSMQMetrics.ps1"
        Arguments   = ""
    },
    @{
        Name        = "T360-Datadog-EphemeralPorts-Metrics"
        Description = "Sends ephemeral port metrics to Datadog every minute (T360 Item 13)"
        Script      = "Send-EphemeralPortMetrics.ps1"
        Arguments   = "-AutoRestart"
    }
)

# ──────────────────────────────────────────────────────────────────────────────
# Uninstall
# ──────────────────────────────────────────────────────────────────────────────
if ($Uninstall) {
    Write-Host "Removing T360 Datadog scheduled tasks..." -ForegroundColor Yellow
    foreach ($Task in $Tasks) {
        $Existing = Get-ScheduledTask -TaskName $Task.Name -ErrorAction SilentlyContinue
        if ($Existing) {
            Unregister-ScheduledTask -TaskName $Task.Name -Confirm:$false
            Write-Host "  Removed: $($Task.Name)" -ForegroundColor Green
        }
        else {
            Write-Host "  Not found: $($Task.Name)" -ForegroundColor Gray
        }
    }
    Write-Host "Done." -ForegroundColor Green
    exit 0
}

# ──────────────────────────────────────────────────────────────────────────────
# Install
# ──────────────────────────────────────────────────────────────────────────────

# Create script directory
if (-not (Test-Path $ScriptPath)) {
    New-Item -ItemType Directory -Path $ScriptPath -Force | Out-Null
    Write-Host "Created directory: $ScriptPath"
}

# Create log directory
$LogPath = "C:\Logs\Datadog"
if (-not (Test-Path $LogPath)) {
    New-Item -ItemType Directory -Path $LogPath -Force | Out-Null
    Write-Host "Created log directory: $LogPath"
}

# Copy scripts to deployment location
$SourceDir = $PSScriptRoot
foreach ($Task in $Tasks) {
    $SourceFile = Join-Path $SourceDir $Task.Script
    $DestFile = Join-Path $ScriptPath $Task.Script

    if (Test-Path $SourceFile) {
        Copy-Item -Path $SourceFile -Destination $DestFile -Force
        Write-Host "Deployed: $($Task.Script) -> $DestFile"
    }
    else {
        Write-Warning "Source script not found: $SourceFile"
        Write-Warning "Please copy $($Task.Script) to $ScriptPath manually."
    }
}

# Create scheduled tasks
Write-Host "`nCreating scheduled tasks..." -ForegroundColor Cyan

foreach ($Task in $Tasks) {
    $TaskScript = Join-Path $ScriptPath $Task.Script

    # Check if task already exists
    $Existing = Get-ScheduledTask -TaskName $Task.Name -ErrorAction SilentlyContinue
    if ($Existing) {
        Write-Host "  Task '$($Task.Name)' already exists. Updating..." -ForegroundColor Yellow
        Unregister-ScheduledTask -TaskName $Task.Name -Confirm:$false
    }

    # Create trigger: every 1 minute, indefinitely
    $Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::MaxValue)

    # Create action
    $ActionArgs = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$TaskScript`""
    if ($Task.Arguments) {
        $ActionArgs += " $($Task.Arguments)"
    }
    $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument $ActionArgs -WorkingDirectory $ScriptPath

    # Create settings
    $Settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 1) `
        -MultipleInstances IgnoreNew

    # Create principal (run as SYSTEM)
    $Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Register task
    Register-ScheduledTask `
        -TaskName $Task.Name `
        -Description $Task.Description `
        -Trigger $Trigger `
        -Action $Action `
        -Settings $Settings `
        -Principal $Principal `
        -Force

    Write-Host "  Created: $($Task.Name)" -ForegroundColor Green
}

# ──────────────────────────────────────────────────────────────────────────────
# Verify
# ──────────────────────────────────────────────────────────────────────────────
Write-Host "`n=== Verification ===" -ForegroundColor Cyan
foreach ($Task in $Tasks) {
    $Registered = Get-ScheduledTask -TaskName $Task.Name -ErrorAction SilentlyContinue
    if ($Registered) {
        Write-Host "  [OK] $($Task.Name) - Status: $($Registered.State)" -ForegroundColor Green

        # Run immediately to test
        Write-Host "       Running initial test..." -ForegroundColor Gray
        Start-ScheduledTask -TaskName $Task.Name
        Start-Sleep -Seconds 5
        $TaskInfo = Get-ScheduledTaskInfo -TaskName $Task.Name
        Write-Host "       Last result: $($TaskInfo.LastTaskResult)" -ForegroundColor Gray
    }
    else {
        Write-Host "  [FAIL] $($Task.Name) - Not registered!" -ForegroundColor Red
    }
}

Write-Host "`n=== Installation Complete ===" -ForegroundColor Green
Write-Host "Scripts deployed to: $ScriptPath"
Write-Host "Logs will be written to: $LogPath"
Write-Host "Tasks run every 1 minute as SYSTEM."
Write-Host "`nTo uninstall: .\Install-ScheduledTasks.ps1 -Uninstall"
