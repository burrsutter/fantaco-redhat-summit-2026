# OpenClaw traces in CloudWatch

Use this integration only for an AWS installation. It is optional and is not
part of the OCP/ODF installation. The setup commands require the explicit
`INSTALLATION_TYPE=aws` opt-in. `SITE_NAME=ocp` selects the OpenShift broker
route in either installation and does not identify the cloud provider.

The OpenClaw diagnostics plugin sends OTLP/HTTP spans to a two-replica collector
in `trace-forwarder`. One collector pipeline sends the original spans to the
existing MLflow experiment; the other removes span events and all attributes
except the metadata allowlist before sending spans to CloudWatch Transaction
Search. The separate Langfuse plugin continues to send its traces directly to
Langfuse. No prompt, response, or tool body is sent to CloudWatch.

## Setup

Set `KUBECONFIG` to the logged-in target cluster and configure the AWS CLI for
the AWS account and region hosting it. `AWS_REGION` can override the CLI region.
Confirm the account and cluster before enabling the account-wide X-Ray trace
destination and indexing rule:

```bash
export INSTALLATION_TYPE=aws
aws sts get-caller-identity
oc whoami --show-server
./setup-cloudwatch-traces-aws.py
aws xray get-trace-segment-destination
```

Wait for `Status: ACTIVE`, then deploy the collector and opt in the seats:

```bash
./deploy-cloudwatch-traces.sh
./enable-cloudwatch-traces-seats.py 1 150 --site ocp --parallel 5
oc get deployment trace-collector -n trace-forwarder
oc adm top pods -n trace-forwarder
```

The setup script derives the IAM role name, AWS account, region, and OIDC issuer
from the connected environment. It scopes role assumption to the collector
service account and grants only X-Ray trace publication. It sets the default
trace summary indexing rate to 1%; Transaction Search still ingests all spans.
The seat script labels each namespace, sets the operator-supported
`spec.network.inClusterBypass` field, permits egress only to the collector on
port 4318, waits for the gateway, and restores its OpenClaw configuration. It
does not reset broker assignments or audience history.

## Show it during the demo

1. Open the [CloudWatch console](https://console.aws.amazon.com/cloudwatch/) in
   the cluster's AWS account and region. In the left navigation, expand
   **Application Signals** and select **Transaction Search**. Set the time
   window to the last 15 minutes and choose the **List** view. Do not use the
   `/aws/application-signals/data` log group: its JSON records are aggregated
   metrics, not the individual trace spans.
2. Ask an audience seat to make a request in OpenClaw. Filter for service name
   `openclaw-agentic-user<N>`, using the assigned seat number. Open a span to
   show timing, model name, token counts when present, and the operation/phase.
   Prompt and response text are deliberately absent in CloudWatch.
3. Open the same seat's full application trace in the MLflow
   `openclaw-traces` experiment, or show the Langfuse trace. These existing
   views retain their original tracing paths and content.

If Transaction Search is slow to show a new span, open **Logs Insights**, select
the `aws/spans` log group, and run:

```text
fields @timestamp, name, traceId, durationNano
| filter @message like /openclaw-agentic-user/
| sort @timestamp desc
| limit 50
```

To find a particular trace from an Application Signals exemplar, replace the
filter line with `| filter traceId = "<exemplar-trace-id>"` and set the time
window around the exemplar timestamp. Open a matching result to inspect its
span fields.

You can narrow the filter to an exact service such as
`openclaw-agentic-user150`. The `traceId` is useful for correlating a span with
the OpenClaw or MLflow trace. CloudWatch can take a short time to ingest new
spans; refresh the result after the OpenClaw response completes.

## Check health

```bash
oc get pods -n trace-forwarder -o wide
oc logs -n trace-forwarder deployment/trace-collector --since=10m
aws xray get-trace-segment-destination
aws logs describe-log-groups --log-group-name-prefix aws/spans
```

The collector reserves 100m CPU and 256Mi memory per replica, with limits of
one CPU and 512Mi. It spreads replicas across workers and keeps at least one
available during voluntary disruptions. Its queue is in memory, so a collector
restart during an AWS outage can lose queued spans; MLflow and Langfuse remain
independent destinations.

CloudWatch Transaction Search setup and usage follow the
[AWS setup guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Enable-TransactionSearch.html)
and [span search guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Transaction-Search-search-analyze-spans.html).
