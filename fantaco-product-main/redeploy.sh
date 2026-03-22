#!/usr/bin/env bash

oc apply -f deployment/kubernetes/application/configmap.yaml
oc apply -f deployment/kubernetes/application/secret.yaml
oc apply -f deployment/kubernetes/application/deployment.yaml
oc apply -f deployment/kubernetes/application/service.yaml

oc delete pod -l app=fantaco-product-main
