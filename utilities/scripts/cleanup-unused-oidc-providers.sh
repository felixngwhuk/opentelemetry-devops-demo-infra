#!/usr/bin/env bash
set -euo pipefail

# Delete unused IAM OIDC providers:
# - For each IAM OIDC provider, check if any IAM role trust policy references it
# - If none, delete the provider

DRY_RUN="${DRY_RUN:-true}"   # set DRY_RUN=false to actually delete

echo "DRY_RUN=$DRY_RUN"
echo "Fetching OIDC providers..."

mapfile -t PROVIDER_ARNS < <(aws iam list-open-id-connect-providers \
  --query 'OpenIDConnectProviderList[].Arn' --output text | tr '\t' '\n')

if [[ ${#PROVIDER_ARNS[@]} -eq 0 ]]; then
  echo "No OIDC providers found."
  exit 0
fi

echo "Found ${#PROVIDER_ARNS[@]} OIDC provider(s)."

for arn in "${PROVIDER_ARNS[@]}"; do
  echo "------------------------------------------------------------"
  echo "Provider: $arn"

  # Provider URL comes back like: oidc.eks.eu-west-2.amazonaws.com/id/XXXXX (no https://)
  url="$(aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$arn" \
    --query 'Url' --output text)"

  if [[ -z "$url" || "$url" == "None" ]]; then
    echo "Could not read provider URL, skipping: $arn"
    continue
  fi

  echo "Provider URL: $url"
  echo "Scanning IAM roles for trust references..."

  # Iterate roles and detect any that reference this provider URL in their trust policy.
  # We do a 2-step approach:
  #  1) list role names
  #  2) for each role, fetch trust policy and check for URL substring
  #
  # This is reliable, but can be slow in very large accounts.

  trusted_roles=()

  # Get all role names
  mapfile -t ROLE_NAMES < <(aws iam list-roles --query 'Roles[].RoleName' --output text | tr '\t' '\n')

  for role_name in "${ROLE_NAMES[@]}"; do
    # Trust policy doc (AssumeRolePolicyDocument) is returned already decoded by AWS CLI output
    trust_doc="$(aws iam get-role --role-name "$role_name" \
      --query 'Role.AssumeRolePolicyDocument' --output json)"

    # Check if trust policy references this provider URL.
    # This catches common patterns:
    #  - "Federated": "arn:aws:iam::<acct>:oidc-provider/<url>"
    #  - Condition keys like "<url>:sub" / "<url>:aud"
    if echo "$trust_doc" | grep -Fq "$url"; then
      trusted_roles+=("$role_name")
    fi
  done

  if [[ ${#trusted_roles[@]} -gt 0 ]]; then
    echo "✅ Provider is still trusted by ${#trusted_roles[@]} role(s):"
    printf ' - %s\n' "${trusted_roles[@]}"
    echo "Skipping deletion."
  else
    echo "⚠️  No roles trust this provider."
    if [[ "$DRY_RUN" == "true" ]]; then
      echo "[DRY RUN] Would delete: $arn"
    else
      echo "Deleting: $arn"
      aws iam delete-open-id-connect-provider --open-id-connect-provider-arn "$arn"
      echo "🗑️   Deleted: $arn"
    fi
  fi
done

echo "Done."