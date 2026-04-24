#!/usr/bin/env bash
while true; do
  oc get projects -o name | grep '^project.project.openshift.io/dev' | sed 's|project.project.openshift.io/||'
  sleep 2
done
