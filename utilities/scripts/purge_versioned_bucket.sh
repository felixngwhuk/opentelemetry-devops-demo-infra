#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./purge_versioned_bucket.sh <bucket-name> [region]
#
# Dry-run (default):
#   ./purge_versioned_bucket.sh my-bucket eu-west-2
#
# Real delete:
#   DRY_RUN=false ./purge_versioned_bucket.sh my-bucket eu-west-2

BUCKET="${1:-}"
REGION="${2:-}"
DRY_RUN="${DRY_RUN:-true}"

if [[ -z "$BUCKET" ]]; then
  echo "Usage: $0 <bucket-name> [region]"
  exit 1
fi

aws_cmd() {
  if [[ -n "$REGION" ]]; then
    aws --region "$REGION" "$@"
  else
    aws "$@"
  fi
}

echo "Bucket: $BUCKET"
echo "Region: ${REGION:-<default>}"
echo "DRY_RUN: $DRY_RUN"
echo

if [[ "$DRY_RUN" != "true" ]]; then
  read -r -p "⚠️  This will DELETE ALL versions & delete-markers in s3://$BUCKET . Type DELETE to continue: " CONFIRM
  if [[ "$CONFIRM" != "DELETE" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

TOKEN=""
TOTAL=0
BATCH=0

while :; do
  if [[ -n "$TOKEN" ]]; then
    PAGE_JSON="$(aws_cmd s3api list-object-versions --bucket "$BUCKET" --max-items 1000 --starting-token "$TOKEN" --output json)"
  else
    PAGE_JSON="$(aws_cmd s3api list-object-versions --bucket "$BUCKET" --max-items 1000 --output json)"
  fi

  # Create a delete payload for this page (Objects: [{Key, VersionId}, ...])
  DELETE_FILE="$TMPDIR/delete_$BATCH.json"
  COUNT="$(python3 - <<'PY'
import json, sys
d = json.loads(sys.stdin.read())

objs = []
for v in d.get("Versions", []):
    k = v.get("Key")
    vid = v.get("VersionId")
    if k and vid:
        objs.append({"Key": k, "VersionId": vid})

for m in d.get("DeleteMarkers", []):
    k = m.get("Key")
    vid = m.get("VersionId")
    if k and vid:
        objs.append({"Key": k, "VersionId": vid})

out = {"Objects": objs, "Quiet": True}
print(len(objs))
PY
<<<"$PAGE_JSON")"

  # Get next token (if any)
  NEXT_TOKEN="$(python3 - <<'PY'
import json, sys
d = json.loads(sys.stdin.read())
print(d.get("NextToken",""))
PY
<<<"$PAGE_JSON")"

  if [[ "$COUNT" == "0" ]]; then
    if [[ -z "$NEXT_TOKEN" ]]; then
      echo "No more versions/delete-markers found."
      break
    else
      TOKEN="$NEXT_TOKEN"
      continue
    fi
  fi

  # Write payload JSON file
  python3 - <<'PY' > "$DELETE_FILE"
import json, sys
d = json.loads(sys.stdin.read())

objs = []
for v in d.get("Versions", []):
    k = v.get("Key")
    vid = v.get("VersionId")
    if k and vid:
        objs.append({"Key": k, "VersionId": vid})

for m in d.get("DeleteMarkers", []):
    k = m.get("Key")
    vid = m.get("VersionId")
    if k and vid:
        objs.append({"Key": k, "VersionId": vid})

out = {"Objects": objs, "Quiet": True}
print(json.dumps(out))
PY
<<<"$PAGE_JSON"

  BATCH=$((BATCH+1))
  TOTAL=$((TOTAL+COUNT))
  echo "Batch #$BATCH: items=$COUNT (running total=$TOTAL)"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  DRY-RUN: not deleting. (Set DRY_RUN=false to actually delete)"
  else
    aws_cmd s3api delete-objects --bucket "$BUCKET" --delete "file://$DELETE_FILE" >/dev/null
    echo "  Deleted batch #$BATCH"
  fi

  if [[ -z "$NEXT_TOKEN" ]]; then
    break
  fi
  TOKEN="$NEXT_TOKEN"
done

echo
echo "Done. Total objects versions + delete markers processed: $TOTAL"
echo
echo "If you also want to delete the now-empty bucket:"
echo "  aws ${REGION:+--region $REGION} s3api delete-bucket --bucket $BUCKET"
