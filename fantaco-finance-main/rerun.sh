#!/usr/bin/env bash

podman run -d \
  --name fantaco-finance-main \
  -p 8082:8082 \
  -e SPRING_DATASOURCE_URL=jdbc:postgresql://host.docker.internal:5432/fantaco_finance \
  -e SPRING_DATASOURCE_USERNAME=postgres \
  -e SPRING_DATASOURCE_PASSWORD=postgres \
  docker.io/burrsutter/fantaco-finance-main:1.0.0
