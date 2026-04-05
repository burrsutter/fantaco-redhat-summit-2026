---
name: build-container-image
description: Build and push a container image using podman with the correct platform for OpenShift (linux/amd64)
argument-hint: "<image-name> [context-dir]"
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

# Build Container Image for OpenShift

Build a container image using `podman` with `--platform linux/amd64` and optionally push it to a registry.

**CRITICAL:** This project deploys to OpenShift on amd64 nodes (AWS EC2). macOS Apple Silicon builds produce arm64 images that cause `Exec format error` at runtime. ALWAYS use `--platform linux/amd64`.

## Step 1: Locate the Dockerfile

If `$ARGUMENTS` provides a context directory, use it. Otherwise look for a `Dockerfile` or `Containerfile` in the current directory or ask the user.

```bash
ls Dockerfile Containerfile 2>/dev/null
```

If neither exists, ask the user which directory contains the Dockerfile.

## Step 2: Determine the image name and tag

If `$ARGUMENTS` provides an image name, use it. Otherwise ask the user:
- Registry (default: `quay.io`)
- Organization/username
- Image name
- Tag (default: `latest`)

## Step 3: Build the image

```bash
podman build --platform linux/amd64 -t <full-image-name> <context-dir>
```

**NEVER omit `--platform linux/amd64`.** This is the single most important flag. Without it, the image will be built for the local architecture (arm64 on Apple Silicon Macs) and will fail on OpenShift with `Exec format error`.

If the build fails, show the error and suggest fixes.

## Step 4: Ask about pushing

Ask the user with `AskUserQuestion`: "Push the image to the registry?"

- **Yes** — push the image
- **No** — skip, just report the local image

If yes:

```bash
podman push <full-image-name>
```

## Step 5: Report

Tell the user:
- Image name and tag
- Platform: `linux/amd64`
- Whether it was pushed
- Remind them to update the deployment image reference if needed
