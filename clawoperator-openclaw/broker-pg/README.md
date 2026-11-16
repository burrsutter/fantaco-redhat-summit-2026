# PostgreSQL session broker

The broker stores routes, audience codes, and exclusive seat assignments in
PostgreSQL. Its connection uses the standard `PGHOST`, `PGPORT`, `PGDATABASE`,
`PGUSER`, and `PGPASSWORD` variables. Set `PGSSL_CA_PATH` to a trusted CA file
when the database uses a private certificate, or `PGSSL=true` when the server
certificate chains to a system CA. The app has no cloud provider dependency.

On OpenShift, `deploy-broker-ocp.sh --rebuild` installs the certified
CloudNativePG operator, creates a three-instance PostgreSQL cluster on the
default StorageClass, builds the broker image, and runs two broker replicas.
The replicas are placed on separate nodes. A PodDisruptionBudget keeps one
available during voluntary maintenance; an HPA may scale the broker to four.
The database acknowledges writes after one standby has received them.

The current ROSA workers are all in one availability zone, so this protects
against a worker failure but not an availability-zone failure. Moving to a
cluster with workers in multiple zones can spread the same manifests across
zones without changing the broker code.

After deployment, run `update-broker-ocp.sh` to load the audience routes.
The first reload initializes the audience code in an empty database. Further
reloads preserve assignments for unchanged route hosts. A reset deliberately
releases every assignment.

When replacing a running SQLite broker, sync its latest routes first, then
seed the new PostgreSQL database with `openshift/broker-db-seed.yaml` before
applying the new broker Deployment. Copy the generated, gitignored
`routes-ocp.csv` into the seed Job pod at `/tmp/routes.csv` and wait for the
Job to finish. This lets the old and new broker pods serve the same audience
code during the rolling cutover. Once the PostgreSQL broker passes the live
checks, the old `session-broker-data` PVC can be removed.

Before switching a fresh database into service, run the isolated
`openshift/broker-db-smoke.yaml` Job. It claims 130 test seats with 160
concurrent requests, checks that each claim is unique, and clears the test
routes and assignments. Do not run this Job against an active audience: it
uses the broker's database and clears its routes at the end.
