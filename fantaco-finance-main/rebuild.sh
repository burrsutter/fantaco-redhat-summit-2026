#!/usr/bin/env bash

mvn clean compile package

podman build --arch amd64 --os linux -t docker.io/burrsutter/fantaco-finance-main:1.0.0 -f deployment/Dockerfile .
podman push docker.io/burrsutter/fantaco-finance-main:1.0.0
