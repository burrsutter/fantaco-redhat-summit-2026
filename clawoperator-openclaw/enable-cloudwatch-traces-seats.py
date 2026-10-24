#!/usr/bin/env python3
"""Connect existing OpenClaw seats to the optional trace fan-out collector.

Usage: KUBECONFIG=... ./enable-cloudwatch-traces-seats.py 1 150 --site ocp
The Claw network fields are managed by the operator; do not patch its Deployment.
"""

import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent
COLLECTOR_URL = "http://trace-collector.trace-forwarder.svc.cluster.local:4318/v1/traces"
EGRESS = {
    "to": [{"namespaceSelector": {"matchLabels": {"kubernetes.io/metadata.name": "trace-forwarder"}}}],
    "ports": [{"port": 4318, "protocol": "TCP"}],
}


def run(*args, timeout=180):
    result = subprocess.run(args, cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{' '.join(args[:5])}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout


def configure_seat(number, site):
    namespace = f"agentic-user{number}"
    claw = json.loads(run("oc", "get", "claw", "instance", "-n", namespace, "-o", "json"))
    network = claw["spec"].get("network") or {}
    egress = network.get("additionalEgress") or []
    if EGRESS not in egress:
        egress.append(EGRESS)
    network["additionalEgress"] = egress
    network["inClusterBypass"] = True
    run("oc", "patch", "claw", "instance", "-n", namespace, "--type=merge", "-p",
        json.dumps({"spec": {"network": network}}))
    run("oc", "label", "namespace", namespace, "trace-forwarder-client=true", "--overwrite")

    # Wait for the operator's network and proxy reconciliation before repatching.
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        deployment = json.loads(run("oc", "get", "deployment", "instance", "-n", namespace, "-o", "json"))
        containers = deployment["spec"]["template"]["spec"]["containers"]
        gateway = next(container for container in containers if container["name"] == "gateway")
        environment = {item["name"]: item.get("value", "") for item in gateway.get("env", [])}
        if ".svc.cluster.local" in environment.get("NO_PROXY", ""):
            break
        time.sleep(2)
    else:
        raise RuntimeError("operator did not enable in-cluster bypass")

    run("oc", "rollout", "status", "deployment/instance", "-n", namespace, "--timeout=180s", timeout=210)
    run(str(ROOT / "post-restart-repatch.sh"), "--site", site, namespace, timeout=180)
    endpoint = run("oc", "exec", "deployment/instance", "-n", namespace, "-c", "gateway", "--",
                   "node", "-e", "const c=require('/home/node/.openclaw/openclaw.json');"
                   "console.log(c.env?.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT||'')").strip()
    if endpoint != COLLECTOR_URL:
        raise RuntimeError(f"unexpected OTLP endpoint: {endpoint}")
    return namespace


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("start", type=int)
    parser.add_argument("end", type=int)
    parser.add_argument("--site", default=os.environ.get("SITE_NAME", "ocp"))
    parser.add_argument("--parallel", type=int, default=5)
    args = parser.parse_args()
    if args.start < 1 or args.end < args.start or args.parallel < 1:
        parser.error("invalid seat range or parallel count")
    if os.environ.get("INSTALLATION_TYPE") != "aws":
        parser.error("CloudWatch traces require INSTALLATION_TYPE=aws; skip this step for OCP/ODF")
    if not os.environ.get("KUBECONFIG"):
        parser.error("set KUBECONFIG to the target cluster's logged-in kubeconfig")
    if run("oc", "get", "deployment", "trace-collector", "-n", "trace-forwarder", "-o",
           "jsonpath={.status.readyReplicas}").strip() != "2":
        parser.error("trace collector must have two ready replicas")

    failures = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallel) as pool:
        futures = {pool.submit(configure_seat, number, args.site): number
                   for number in range(args.start, args.end + 1)}
        for future in concurrent.futures.as_completed(futures):
            number = futures[future]
            try:
                print(f"agentic-user{number}: ready", flush=True) if future.result() else None
            except Exception as error:
                failures.append(number)
                print(f"agentic-user{number}: FAILED: {error}", file=sys.stderr, flush=True)
    print(f"Configured {args.end - args.start + 1 - len(failures)} seats; failed: {failures}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
