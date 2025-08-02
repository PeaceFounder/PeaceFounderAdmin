#!/bin/bash

set -e

# Stop and cleanup existing containers
podman stop peacefounder registrar-demo 2>/dev/null || true
podman rm peacefounder registrar-demo 2>/dev/null || true
podman secret rm registrar_token 2>/dev/null || true

# Build images
podman build -t peacefounder .
podman build -t registrar-demo examples/integration

# Create secret
openssl rand -hex 32 | podman secret create registrar_token -

# Start services
podman run -d --name peacefounder \
  -p 127.0.0.1:3221:3221 -p 4584:4584 \
  --secret registrar_token \
  peacefounder:latest --load=./examples/integration/setup.jl

podman run -d --name registrar-demo \
  -p 3456:3456 \
  --secret registrar_token \
  -e PEACEFOUNDER_SERVICE=http://host.containers.internal:4584 \
  registrar-demo:latest

echo "Demo started:"
echo "  PeaceFounder admin panel: http://127.0.0.1:3221"
echo "  PeaceFounder service: http://0.0.0.0:4584"
echo "  Registrar integration: http://0.0.0.0:3456"

