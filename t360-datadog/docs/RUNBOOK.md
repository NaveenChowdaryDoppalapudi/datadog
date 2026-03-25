# T360 Datadog Monitoring — Operational Runbook

## Overview

This runbook covers day-to-day operations for the T360 Datadog monitoring system that replaces the manual IPM 12-point checklist.

**Cluster:** `zuse1-d003-b066-aks-p1-t360-b`  
**Subscription:** `D003-B066-ELM-Z-PRD-001`  
**Dashboard:** Datadog > Dashboards > "T360 Production - 13 Point Health Check"

---

## Daily Operations

### Scheduled Reports (Replaces 8 AM / 1 PM / 6 PM Checks)

Datadog monitors run continuously, but to maintain the same reporting cadence:

1. Go to **Dashboards > T360 Production - 13 Point Health Check**
2. Click **Configure > Scheduled Reports**
3. Set up 3 reports:
   - 8:00 AM CST to `#t360-daily-reports` Slack channel
   - 1:00 PM CST to `#t360-daily-reports` Slack channel
   - 6:00 PM CST to `#t360-daily-reports` Slack channel
4. Each report will contain a snapshot of all 13 checkpoint widgets

### Checking Monitor Status

- **Quick view:** Monitors > Manage Monitors > Filter by tag `app:t360`
- **Dashboard:** The "All T360 Monitor Status" widget shows a real-time count of OK/Warn/Alert monitors
- **Mobile:** Install the Datadog mobile app for push notifications

---

## Alert Response Procedures

### Item 1: Pods Not Running

**Severity:** P1  
**Notification:** Slack + PagerDuty

```bash
# Check pod status
kubectl get pods -n <namespace> --field-selector=status.phase!=Running

# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check recent events
kubectl get events -n <namespace> --sort-by='.lastTimestamp' | tail -20

# Check node resources
kubectl top nodes
kubectl top pods -n <namespace> --sort-by=cpu
```

**Common causes:** Image pull failures, resource limits exceeded, node pressure, CrashLoopBackOff.

### Items 2-3: FTP/SMTP Server Down

**Severity:** P1  
**Notification:** Slack + PagerDuty  
**Action:** Create INCIDENT ticket immediately

1. Verify service is actually down (not a network blip — Datadog retries 2x before alerting)
2. Check the server directly:
   - FTP: `telnet <ftp-host> 21`
   - SMTP: `telnet <smtp-host> 587`
3. Check Windows service on the host
4. Check firewall rules / NSG changes
5. Create incident ticket per standard process

### Items 4-6: Database Issues

**Severity:** P1  
**Notification:** Slack DBA channel + DBA PagerDuty

**Blocking (Item 4):**
1. Check Datadog DBM > Live Queries > Waiting Queries
2. Identify the blocking session and blocked sessions
3. DBA decision: kill the blocker or wait

**Performance (Item 5):**
1. Check Datadog DBM > Query Metrics for top consumers
2. Look for query plan regressions
3. Check Azure SQL DTU/CPU metrics

**Replication (Item 6):**
1. Check replica health in Azure Portal
2. Verify network between primary and replica
3. If lag > 60s, DBA must investigate

### Item 7: Disk Space High

**Severity:** P2  
**Notification:** Slack

```bash
# Identify large directories
ssh <host>
df -h
du -sh /* 2>/dev/null | sort -rh | head -20

# Common cleanup targets
# - Application logs: /var/log/
# - Temp files: /tmp/
# - Old deployments
```

### Item 8: AKS Node Issues

**Severity:** P1  
**Notification:** Slack + PagerDuty

```bash
# Check node status
kubectl get nodes -o wide
kubectl describe node <node-name>

# Check resource pressure
kubectl top nodes

# If a node is NotReady
kubectl get events --field-selector involvedObject.kind=Node
```

**For high CPU/Memory:** Scale the node pool or identify resource-hungry pods.

### Item 9: VM Down

**Severity:** P1  
**Notification:** Slack + PagerDuty

1. Check Azure Portal > Virtual Machines > status
2. If deallocated: start the VM
3. If running but agent down: RDP/SSH in and restart Datadog Agent
4. If unreachable: check Azure service health, NSG rules

### Item 10: MSMQ Queue Not Empty

**Severity:** P2  
**Notification:** Slack

1. RDP to `zuse1p1t360itp1.wkrainier.com`
2. Open Computer Management > Message Queuing
3. Check for stuck messages
4. Verify "T360 Network Processing Service" is running
5. If messages are stuck, restart the service

### Item 11: File Share Capacity

**Severity:** P2  
**Notification:** Slack

1. Check current capacity in Datadog dashboard widget
2. If approaching limit:
   - Azure Portal > Storage Account > File shares > t360-prd-share
   - Identify large files or directories
   - Archive or delete old files
   - Consider increasing the share quota

### Item 12: AKS Node Disk > 75%

**Severity:** P1  
**Notification:** Slack + PagerDuty

```bash
# Check disk usage on nodes
kubectl get nodes -o wide
# SSH to affected node (via Azure Serial Console or bastion)

# Clean cached container images
docker system prune -a --filter "until=72h"
# Or: crictl rmi --prune
```

**Follow SOP:** https://confluence.wolterskluwer.io/display/GRCELMNFR/T360+-+SOPs

### Item 13: Ephemeral Port Exhaustion

**Severity:** SEV-3 (if ports <= 4000)  
**Notification:** Slack + PagerDuty

1. Create Sev-3 INCIDENT ticket
2. RDP to `zuse1p1t360itp1.wkrainier.com`
3. Restart "T360 Network Processing Service":
   ```powershell
   Restart-Service -DisplayName "T360 Network Processing Service" -Force
   ```
4. Verify ports recover (check Datadog dashboard)
5. If auto-restart is enabled, the script handles this automatically

**SOP:** https://confluence.wolterskluwer.io/spaces/GRCELMNFR/pages/850418240

---

## Maintenance Procedures

### Updating Monitor Thresholds

```bash
cd terraform/
# Edit environments/production/terraform.tfvars
# Change values in the thresholds block
terraform plan -var-file=environments/production/terraform.tfvars
terraform apply -var-file=environments/production/terraform.tfvars
```

### Adding a New Monitor

1. Add the resource in `terraform/modules/monitors.tf`
2. Add appropriate tags including `app:t360` and `check:item-N-description`
3. Add a widget to the dashboard in `terraform/modules/dashboard.tf`
4. Run `terraform plan` and `terraform apply`

### Upgrading the Datadog Agent

```bash
helm repo update
helm upgrade datadog datadog/datadog \
  -f helm/datadog-values.yaml \
  -n datadog
```

### Muting Monitors During Maintenance

```bash
# Via Datadog UI: Monitors > Manage Downtime
# Or via Terraform: edit terraform/modules/downtime.tf
```

### Checking Custom Metric Delivery (ITP Server)

```powershell
# On zuse1p1t360itp1:
.\scripts\powershell\Test-DatadogConnectivity.ps1

# Check Datadog Agent status
& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" status

# Check DogStatsD stats
& "C:\Program Files\Datadog\Datadog Agent\bin\agent.exe" dogstatsd-stats
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| No data for Items 10/13 | PowerShell scripts not running | Check Task Scheduler on ITP server |
| No data for Item 11 | Azure integration not configured | Enable Azure Storage integration in Datadog |
| No data for Items 4-6 | DBM not enabled | Set up Database Monitoring for SQL Server |
| Agent pods CrashLooping | Resource limits too low | Increase limits in helm/datadog-values.yaml |
| Monitors showing "No Data" | Agent connectivity issue | Check agent status, API key, network egress |
| False alerts on Items 2/3 | Synthetic test location issue | Add additional test locations |

---

## Contacts

| Role | Channel | Escalation |
|------|---------|------------|
| T360 Operations | `#t360-alerts` (Slack) | PagerDuty: t360 service |
| DBA Team | `#t360-dba` (Slack) | PagerDuty: dba-oncall |
| Infrastructure | `#infra-support` (Slack) | PagerDuty: infra service |
