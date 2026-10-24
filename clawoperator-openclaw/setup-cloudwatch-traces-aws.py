#!/usr/bin/env python3
"""Create AWS permissions and enable Transaction Search for the trace collector.

This changes account-wide X-Ray/CloudWatch trace settings. Inspect the target
AWS account, region, and OpenShift cluster before running it.
"""

import json
import os
import re
import subprocess
import sys


def command(*args, parse_json=False):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:4])}: {result.stderr.strip()}")
    return json.loads(result.stdout) if parse_json else result.stdout.strip()


def main():
    if os.environ.get("INSTALLATION_TYPE") != "aws":
        raise RuntimeError("CloudWatch traces require INSTALLATION_TYPE=aws; skip this step for OCP/ODF")
    if not os.environ.get("KUBECONFIG"):
        raise RuntimeError("Set KUBECONFIG to the logged-in target cluster")
    region = os.environ.get("AWS_REGION") or command("aws", "configure", "get", "region")
    if not re.fullmatch(r"[a-z0-9-]+", region):
        raise RuntimeError("Set a valid AWS_REGION")
    account = command("aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text")
    api = command("oc", "whoami", "--show-server")
    match = re.match(r"https://api\.([^.:]+)\.", api)
    if not match:
        raise RuntimeError(f"Cannot derive cluster name from API: {api}")
    cluster = match.group(1)
    issuer = command("oc", "get", "authentication", "cluster", "-o",
                     "jsonpath={.spec.serviceAccountIssuer}").removeprefix("https://")
    if not issuer or "/" not in issuer:
        raise RuntimeError("Cluster has no service account OIDC issuer")
    oidc_arn = f"arn:aws:iam::{account}:oidc-provider/{issuer}"
    command("aws", "iam", "get-open-id-connect-provider", "--open-id-connect-provider-arn", oidc_arn)
    role = os.environ.get("CLOUDWATCH_TRACE_ROLE_NAME", f"{cluster}-cloudwatch-traces")
    if not re.fullmatch(r"[a-zA-Z0-9+=,.@_-]+", role):
        raise RuntimeError("Invalid CLOUDWATCH_TRACE_ROLE_NAME")

    trust = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Principal": {"Federated": oidc_arn},
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {"StringEquals": {
                f"{issuer}:sub": "system:serviceaccount:trace-forwarder:collector",
                f"{issuer}:aud": "sts.amazonaws.com",
            }},
        }],
    }
    policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Effect": "Allow",
            "Action": ["xray:PutTraceSegments", "xray:PutTelemetryRecords"],
            "Resource": "*",
        }],
    }
    existing = subprocess.run(["aws", "iam", "get-role", "--role-name", role],
                              capture_output=True, text=True)
    if existing.returncode:
        command("aws", "iam", "create-role", "--role-name", role,
                "--assume-role-policy-document", json.dumps(trust))
    else:
        command("aws", "iam", "update-assume-role-policy", "--role-name", role,
                "--policy-document", json.dumps(trust))
    command("aws", "iam", "put-role-policy", "--role-name", role,
            "--policy-name", "publish-cloudwatch-traces", "--policy-document", json.dumps(policy))

    logs_policy = {
        "Version": "2012-10-17",
        "Statement": [{
            "Sid": "TransactionSearchXRayAccess",
            "Effect": "Allow",
            "Principal": {"Service": "xray.amazonaws.com"},
            "Action": "logs:PutLogEvents",
            "Resource": [
                f"arn:aws:logs:{region}:{account}:log-group:aws/spans:*",
                f"arn:aws:logs:{region}:{account}:log-group:/aws/application-signals/data:*",
            ],
            "Condition": {
                "ArnLike": {"aws:SourceArn": f"arn:aws:xray:{region}:{account}:*"},
                "StringEquals": {"aws:SourceAccount": account},
            },
        }],
    }
    command("aws", "logs", "put-resource-policy", "--region", region,
            "--policy-name", f"{cluster}-transaction-search",
            "--policy-document", json.dumps(logs_policy))
    destination = command("aws", "xray", "get-trace-segment-destination",
                          "--region", region, parse_json=True)
    if destination.get("Destination") != "CloudWatchLogs":
        command("aws", "xray", "update-trace-segment-destination", "--region", region,
                "--destination", "CloudWatchLogs")
    rules = command("aws", "xray", "get-indexing-rules", "--region", region,
                    parse_json=True).get("IndexingRules", [])
    default_rule = next((item for item in rules if item.get("Name") == "Default"), {})
    percentage = default_rule.get("Rule", {}).get("Probabilistic", {}).get(
        "DesiredSamplingPercentage")
    if percentage != 1.0:
        command("aws", "xray", "update-indexing-rule", "--region", region,
                "--name", "Default", "--rule",
                json.dumps({"Probabilistic": {"DesiredSamplingPercentage": 1.0}}))
    print(f"AWS account {account}, region {region}, cluster {cluster}")
    print(f"Collector role: arn:aws:iam::{account}:role/{role}")
    print("Wait until `aws xray get-trace-segment-destination` reports ACTIVE before sending traces.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
