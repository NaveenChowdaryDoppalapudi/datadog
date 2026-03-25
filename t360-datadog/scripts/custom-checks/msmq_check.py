"""
T360 MSMQ Custom Datadog Agent Check

This is a Python-based Datadog Agent check that monitors MSMQ queue lengths
on Windows servers. Deploy alongside the Datadog Agent on the ITP server.

Installation:
  1. Copy msmq_check.py to: C:\ProgramData\Datadog\checks.d\
  2. Copy msmq_check.yaml to: C:\ProgramData\Datadog\conf.d\msmq_check.d\conf.yaml
  3. Restart the Datadog Agent service

Alternative to the PowerShell DogStatsD approach - this integrates directly
with the Datadog Agent's check framework for better reliability and metadata.
"""

import subprocess
import json

try:
    from datadog_checks.base import AgentCheck, ConfigurationError
except ImportError:
    from checks import AgentCheck

class MSMQCheck(AgentCheck):
    """
    Collects MSMQ queue metrics for T360 ITP monitoring.
    Replaces Item 10 from the 12-point checklist.
    """

    SERVICE_CHECK_NAME = "custom.msmq.can_connect"
    DEFAULT_QUEUE_FILTER = "*"

    def check(self, instance):
        queue_filter = instance.get("queue_filter", self.DEFAULT_QUEUE_FILTER)
        custom_tags = instance.get("tags", [])
        warn_threshold = instance.get("warn_threshold", 1)
        critical_threshold = instance.get("critical_threshold", 5)

        try:
            # Check if MSMQ service is running
            service_status = self._check_msmq_service()
            if not service_status:
                self.service_check(
                    self.SERVICE_CHECK_NAME,
                    AgentCheck.CRITICAL,
                    tags=custom_tags,
                    message="MSMQ service is not running"
                )
                self.gauge("custom.msmq.service_available", 0, tags=custom_tags)
                return

            self.gauge("custom.msmq.service_available", 1, tags=custom_tags)

            # Get queue information via PowerShell
            queues = self._get_queue_info(queue_filter)

            total_messages = 0
            total_bytes = 0
            queue_count = 0

            for queue in queues:
                queue_name = queue.get("QueueName", "unknown")
                message_count = int(queue.get("MessageCount", 0))
                bytes_in_queue = int(queue.get("BytesInQueue", 0))

                # Sanitize queue name for tagging
                safe_name = queue_name.replace("\\", "_").replace("$", "").replace(" ", "_").lower()

                queue_tags = custom_tags + [
                    "queue:{}".format(safe_name),
                    "queue_type:{}".format(queue.get("QueueType", "unknown").lower())
                ]

                # Per-queue metrics
                self.gauge("custom.msmq.queue_length", message_count, tags=queue_tags)
                self.gauge("custom.msmq.queue_bytes", bytes_in_queue, tags=queue_tags)

                total_messages += message_count
                total_bytes += bytes_in_queue
                queue_count += 1

                # Log warning if queue has messages
                if message_count > 0:
                    self.log.warning(
                        "MSMQ queue '%s' has %d messages (expected 0)",
                        queue_name, message_count
                    )

            # Aggregate metrics
            agg_tags = custom_tags + ["queue:all"]
            self.gauge("custom.msmq.total_messages", total_messages, tags=agg_tags)
            self.gauge("custom.msmq.total_bytes", total_bytes, tags=agg_tags)
            self.gauge("custom.msmq.queue_count", queue_count, tags=custom_tags)

            # Service check based on total queue length
            if total_messages >= critical_threshold:
                self.service_check(
                    self.SERVICE_CHECK_NAME,
                    AgentCheck.CRITICAL,
                    tags=custom_tags,
                    message="MSMQ total messages: {} (critical >= {})".format(
                        total_messages, critical_threshold
                    )
                )
            elif total_messages >= warn_threshold:
                self.service_check(
                    self.SERVICE_CHECK_NAME,
                    AgentCheck.WARNING,
                    tags=custom_tags,
                    message="MSMQ total messages: {} (warn >= {})".format(
                        total_messages, warn_threshold
                    )
                )
            else:
                self.service_check(
                    self.SERVICE_CHECK_NAME,
                    AgentCheck.OK,
                    tags=custom_tags,
                    message="MSMQ queues healthy. Total messages: {}".format(total_messages)
                )

            self.log.info(
                "MSMQ check complete: %d queues, %d total messages",
                queue_count, total_messages
            )

        except Exception as e:
            self.log.error("MSMQ check failed: %s", str(e))
            self.service_check(
                self.SERVICE_CHECK_NAME,
                AgentCheck.CRITICAL,
                tags=custom_tags,
                message="MSMQ check error: {}".format(str(e))
            )
            raise

    def _check_msmq_service(self):
        """Check if the MSMQ Windows service is running."""
        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command",
                 "(Get-Service -Name 'MSMQ').Status"],
                capture_output=True, text=True, timeout=30
            )
            return result.stdout.strip() == "Running"
        except Exception as e:
            self.log.error("Failed to check MSMQ service: %s", str(e))
            return False

    def _get_queue_info(self, queue_filter):
        """Get MSMQ queue information via PowerShell."""
        ps_script = """
        $queues = Get-MsmqQueue -ErrorAction SilentlyContinue
        if ($queues) {{
            $filtered = $queues | Where-Object {{ $_.QueueName -like '{filter}' }}
            $result = @()
            foreach ($q in $filtered) {{
                $result += @{{
                    QueueName    = $q.QueueName
                    MessageCount = $q.MessageCount
                    BytesInQueue = $q.BytesInQueue
                    QueueType    = $q.QueueType.ToString()
                }}
            }}
            $result | ConvertTo-Json -Compress
        }} else {{
            '[]'
        }}
        """.format(filter=queue_filter)

        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps_script],
                capture_output=True, text=True, timeout=60
            )

            if result.returncode != 0:
                self.log.error("PowerShell error: %s", result.stderr)
                return []

            output = result.stdout.strip()
            if not output or output == "[]":
                return []

            parsed = json.loads(output)
            # PowerShell returns a single object (not array) if only one queue
            if isinstance(parsed, dict):
                return [parsed]
            return parsed

        except json.JSONDecodeError as e:
            self.log.error("Failed to parse queue JSON: %s", str(e))
            return []
        except Exception as e:
            self.log.error("Failed to get queue info: %s", str(e))
            return []
