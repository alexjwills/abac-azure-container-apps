#!/usr/bin/env bash
# Uploads one tagged test file to each department container,
# plus one untagged file in engineering to prove tags, not containers, decide access.
set -euo pipefail

ACCOUNT="${1:?Usage: $0 <storage-account-name>}"

for dept in engineering finance marketing; do
  file=$(mktemp)
  echo "Test file for the $dept department" > "$file"

  echo "Uploading ${dept}-report.txt with tag department=$dept"
  az storage blob upload \
    --account-name "$ACCOUNT" \
    --container-name "$dept" \
    --name "${dept}-report.txt" \
    --file "$file" \
    --tags "department=$dept" \
    --auth-mode login \
    --overwrite \
    --only-show-errors \
    -o none

  rm "$file"
done

file=$(mktemp)
echo "Engineering file with no tag" > "$file"
echo "Uploading untagged.txt to engineering with no tag"
az storage blob upload \
  --account-name "$ACCOUNT" \
  --container-name engineering \
  --name untagged.txt \
  --file "$file" \
  --auth-mode login \
  --overwrite \
  --only-show-errors \
  -o none
rm "$file"