<#
.SYNOPSIS
    Validates Datadog Agent connectivity and custom metric delivery.

.DESCRIPTION
    Tests DogStatsD connectivity, verifies Datadog Agent is running,
    sends test metrics, and checks scheduled tasks are operational.

.NOTES
    Run on: zuse1p1t360itp1.wkrainier.com
#>

[CmdletBinding()]
param(
    [string]$DogStatsDHost = "127.0.0.1",
    [int]$DogStatsDPort = 8125
)

$Results = @()

function Test-Check {
    param([string]$Name, [scriptblock]$Check)
    try {
        $Result = & $Check
        $Status = if ($Result) { "PASS" } else { "FAIL" }
        $Color = if ($Result) { "Green" } else { "Red" }
    }
    catch {
        $Status = "FAIL"
        $Color = "Red"
        $Result = $_.Exception.Message
    }
    Write-Host "  [$Status] $Name" -ForegroundColor $Color
    if (-not $Result -or $Status -eq "FAIL") {
        Write-Host "         Detail: $Result" -ForegroundColor Gray
    }
    return @{ Name = $Name; Status = $Status; Detail = "$Result" }
}

Write-Host "=== T360 Datadog Connectivity Test ===" -ForegroundColor Cyan
Write-Host ""

# 1. Check Datadog Agent service
Write-Host "1. Datadog Agent Service" -ForegroundColor Yellow
$Results += Test-Check "Agent service running" {
    $Svc = Get-Service -Name "DatadogAgent" -ErrorAction SilentlyContinue
    $Svc -and $Svc.Status -eq "Running"
}

# 2. Check DogStatsD port
Write-Host "`n2. DogStatsD Connectivity" -ForegroundColor Yellow
$Results += Test-Check "DogStatsD port $DogStatsDPort is listening" {
    $Listener = Get-NetUDPEndpoint -LocalPort $DogStatsDPort -ErrorAction SilentlyContinue
    $null -ne $Listener
}

$Results += Test-Check "Can send test metric via DogStatsD" {
    $Payload = "custom.itp.connectivity_test:1|g|#app:t360,test:true"
    $UdpClient = New-Object System.Net.Sockets.UdpClient
    $Bytes = [System.Text.Encoding]::ASCII.GetBytes($Payload)
    $Sent = $UdpClient.Send($Bytes, $Bytes.Length, $DogStatsDHost, $DogStatsDPort)
    $UdpClient.Close()
    $Sent -gt 0
}

# 3. Check MSMQ
Write-Host "`n3. MSMQ Service" -ForegroundColor Yellow
$Results += Test-Check "MSMQ service running" {
    $Svc = Get-Service -Name "MSMQ" -ErrorAction SilentlyContinue
    $Svc -and $Svc.Status -eq "Running"
}

$Results += Test-Check "Can enumerate MSMQ queues" {
    $Queues = Get-MsmqQueue -ErrorAction SilentlyContinue
    $null -ne $Queues
}

# 4. Check Scheduled Tasks
Write-Host "`n4. Scheduled Tasks" -ForegroundColor Yellow
$TaskNames = @("T360-Datadog-MSMQ-Metrics", "T360-Datadog-EphemeralPorts-Metrics")
foreach ($TaskName in $TaskNames) {
    $Results += Test-Check "Task '$TaskName' registered" {
        $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $null -ne $Task
    }
    $Results += Test-Check "Task '$TaskName' is enabled" {
        $Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        $Task -and $Task.State -ne "Disabled"
    }
}

# 5. Check script files
Write-Host "`n5. Script Files" -ForegroundColor Yellow
$ScriptDir = "C:\Scripts\Datadog"
$Scripts = @("Send-MSMQMetrics.ps1", "Send-EphemeralPortMetrics.ps1")
foreach ($Script in $Scripts) {
    $Results += Test-Check "Script exists: $Script" {
        Test-Path (Join-Path $ScriptDir $Script)
    }
}

# 6. Check log directory
Write-Host "`n6. Logging" -ForegroundColor Yellow
$Results += Test-Check "Log directory exists" {
    Test-Path "C:\Logs\Datadog"
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$PassCount = ($Results | Where-Object { $_.Status -eq "PASS" }).Count
$FailCount = ($Results | Where-Object { $_.Status -eq "FAIL" }).Count
$Total = $Results.Count

if ($FailCount -eq 0) {
    Write-Host "All $Total checks PASSED" -ForegroundColor Green
}
else {
    Write-Host "$PassCount/$Total passed, $FailCount FAILED" -ForegroundColor Red
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $Results | Where-Object { $_.Status -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Detail)" -ForegroundColor Red
    }
}
