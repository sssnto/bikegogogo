#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/BikeGoGo.app" >&2
  exit 2
fi

app_path="$1"

if [[ ! -d "$app_path" ]]; then
  echo "App bundle not found: $app_path" >&2
  exit 2
fi

forbidden_strings=(
  "buttonPressed:"
)

found=0
while IFS= read -r -d '' candidate; do
  if ! file -b "$candidate" | grep -q "Mach-O"; then
    continue
  fi

  for forbidden in "${forbidden_strings[@]}"; do
    if strings -a "$candidate" | grep -Fq "$forbidden"; then
      echo "Forbidden API reference '$forbidden' found in $candidate" >&2
      found=1
    fi
  done
done < <(find "$app_path" -type f -print0)

if [[ "$found" -ne 0 ]]; then
  exit 1
fi

echo "No known forbidden API references found in $app_path"
