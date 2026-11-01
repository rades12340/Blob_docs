#!/usr/bin/env bash
# Copies each service's OpenAPI spec from its main branch into docs/api/specs/,
# so the API reference pages always show what's merged. Run before
# `mkdocs build` or `mkdocs serve`. The specs aren't committed here.
set -euo pipefail
cd "$(dirname "$0")/.."

out=docs/api/specs
mkdir -p "$out"

fetch() {
    local name=$1 repo=$2
    curl -fsSL "https://raw.githubusercontent.com/rades12340/$repo/main/openapi.yaml" -o "$out/$name.yaml"
    grep -q '^openapi:' "$out/$name.yaml" || { echo "$repo/openapi.yaml doesn't look like an OpenAPI spec" >&2; exit 1; }
    echo "$out/$name.yaml <- $repo"
}

fetch auth auth_service
fetch blob Blob_storage
