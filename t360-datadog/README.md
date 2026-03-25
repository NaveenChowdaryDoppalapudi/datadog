# T360 Datadog Monitoring Automation

## Overview
Automated replacement for the T360 IPM 12-Point Checklist (+ Item 13) using Datadog.  
**Cluster:** `zuse1-d003-b066-aks-p1-t360-b`  
**Subscription:** `D003-B066-ELM-Z-PRD-001`

Replaces the manual 3x/day (8 AM, 1 PM, 6 PM CST) checklist with continuous 24/7 monitoring, automated alerting, and incident creation.

---

## Directory Structure

```
t360-datadog/
├── README.md                          # This file
├── terraform/
│   ├── main.tf                        # Provider config
│   ├── variables.tf                   # Input variables
│   ├── terraform.tfvars.example       # Example variable values
│   ├── outputs.tf                     # Output values
│   ├── modules/
│   │   ├── monitors.tf                # All 13 Datadog monitors
│   │   ├── dashboard.tf               # Consolidated dashboard
│   │   ├── synthetics.tf              # FTP & SMTP synthetic tests
│   │   ├── slo.tf                     # SLO definitions
│   │   └── downtime.tf                # Scheduled maintenance windows
│   └── environments/
│       └── production/
│           └── terraform.tfvars       # Production values (DO NOT COMMIT)
├── helm/
│   └── datadog-values.yaml            # Helm values for Datadog Agent on AKS
├── scripts/
│   ├── custom-checks/
│   │   ├── msmq_check.py              # Datadog custom Agent check for MSMQ
│   │   └── msmq_check.yaml            # Config for MSMQ check
│   ├── powershell/
│   │   ├── Send-EphemeralPortMetrics.ps1   # ITP ephemeral ports monitor
│   │   ├── Send-MSMQMetrics.ps1            # MSMQ DogStatsD sender
│   │   ├── Install-ScheduledTasks.ps1      # Task Scheduler setup
│   │   └── Test-DatadogConnectivity.ps1    # Validate Datadog agent comms
│   └── bash/
│       ├── deploy.sh                  # Full deployment script
│       ├── validate.sh                # Post-deployment validation
│       └── rollback.sh                # Emergency rollback
├── dashboards/
│   └── t360-consolidated-dashboard.json   # Importable Datadog dashboard JSON
└── docs/
    └── RUNBOOK.md                     # Operational runbook
```

---

## Prerequisites

| # | Requirement | Details |
|---|------------|---------|
| 1 | Datadog account | Enterprise plan with APM, DBM, and Synthetics |
| 2 | Datadog API & App keys | Generate at Organization Settings > API Keys |
| 3 | Terraform >= 1.5 | [Install guide](https://developer.hashicorp.com/terraform/install) |
| 4 | Helm >= 3.x | [Install guide](https://helm.sh/docs/intro/install/) |
| 5 | Azure CLI | Authenticated with subscription access |
| 6 | kubectl | Configured for target AKS cluster |
| 7 | PowerShell 5.1+ | On ITP server (zuse1p1t360itp1.wkrainier.com) |

---

## Quick Start

### 1. Clone and configure
```bash
git clone <repo-url>
cd t360-datadog

# Copy and fill in your values
cp terraform/terraform.tfvars.example terraform/environments/production/terraform.tfvars
# Edit with your API keys, hostnames, thresholds
```

### 2. Deploy Datadog Agent to AKS
```bash
bash scripts/bash/deploy.sh --step agent
```

### 3. Deploy Terraform monitors
```bash
bash scripts/bash/deploy.sh --step terraform
```

### 4. Install custom metrics on ITP server
```bash
# On zuse1p1t360itp1.wkrainier.com (PowerShell Admin):
.\scripts\powershell\Install-ScheduledTasks.ps1
```

### 5. Validate
```bash
bash scripts/bash/validate.sh
```

---

## Checkpoint-to-Monitor Mapping

| Item | Checkpoint | Datadog Monitor | Metric Source |
|------|-----------|----------------|---------------|
| 1 | Pods Availability | Metric Alert | Kubernetes integration |
| 2 | FTP Server | Synthetic TCP Test | Datadog Synthetics |
| 3 | SMTP Server | Synthetic TCP Test | Datadog Synthetics |
| 4 | DB Blocking | Metric Alert | Database Monitoring (DBM) |
| 5 | DB Performance | Metric Alert | Azure SQL + DBM |
| 6 | Replication | Metric Alert | DBM / Custom metric |
| 7 | Disk Space | Metric Alert | System Agent |
| 8 | AKS Node Availability | Multi-Alert (CPU + Memory) | Kubernetes integration |
| 9 | VM Availability | Service Check | Agent heartbeat |
| 10 | ITP MSMQ | Metric Alert | Custom check / DogStatsD |
| 11 | File Share Size | Metric Alert | Azure Storage integration |
| 12 | AKS Node Disk | Metric Alert | Kubernetes integration |
| 13 | ITP Ephemeral Ports | Metric Alert | DogStatsD (PowerShell) |

---

## Notification Channels

Configure these before deploying monitors:
- `@slack-t360-alerts` — Primary alerting channel
- `@pagerduty-t360` — On-call escalation
- `@slack-t360-dba` — Database team alerts (Items 4-6)
- `@pagerduty-dba-oncall` — DBA on-call escalation

---

## Maintenance

- **Dashboard**: Import `dashboards/t360-consolidated-dashboard.json` via Datadog UI
- **Scheduled Reports**: Configure in Datadog at Dashboards > Scheduled Reports for 8 AM, 1 PM, 6 PM CST snapshots
- **Runbook**: See `docs/RUNBOOK.md` for operational procedures
