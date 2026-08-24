#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ZONE_ID="$(python3 - <<'PY'
import re
print(re.search(r'cloudflare_zone_id\s*=\s*"([^"]+)"', open("terraform.tfvars").read()).group(1))
PY
)"

TOKEN="${CLOUDFLARE_API_TOKEN:-}"
if [[ -z "$TOKEN" ]]; then
  TOKEN="$(python3 - <<'PY'
import re, os
t = open("terraform.tfvars").read()
m = re.search(r'cloudflare_api_token\s*=\s*"([^"]+)"', t)
print(m.group(1) if m else "")
PY
)"
fi
if [[ -z "$TOKEN" ]]; then
  echo "Set CLOUDFLARE_API_TOKEN (Zone WAF Edit + Zone Read). dns-token is not enough." >&2
  exit 1
fi
export CLOUDFLARE_API_TOKEN="$TOKEN"

python3 - "$ZONE_ID" <<'PY'
import json, os, sys, urllib.request, urllib.error

zone = sys.argv[1]
token = os.environ["CLOUDFLARE_API_TOKEN"]
url = (
    f"https://api.cloudflare.com/client/v4/zones/{zone}"
    f"/rulesets/phases/http_request_firewall_custom/entrypoint"
)
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
try:
    with urllib.request.urlopen(req) as resp:
        body = json.load(resp)
except urllib.error.HTTPError as e:
    print(e.read().decode(), file=sys.stderr)
    sys.exit(1)

if not body.get("success"):
    print(json.dumps(body, indent=2), file=sys.stderr)
    sys.exit(1)

result = body["result"]
ruleset_id = result["id"]
name = result.get("name") or "default"
print(f"ruleset_id={ruleset_id}")
print(f"name={name}")
print(f"rules={len(result.get('rules') or [])}")

skip_ref = "skip_authentik_oidc_endpoints"
extras = []
for rule in result.get("rules") or []:
    if rule.get("ref") == skip_ref:
        continue
    keep = {
        k: rule[k]
        for k in (
            "ref",
            "description",
            "enabled",
            "action",
            "expression",
            "action_parameters",
            "logging",
            "ratelimit",
            "exposed_credential_check",
        )
        if k in rule and rule[k] is not None
    }
    if "ref" not in keep and rule.get("id"):
        keep["ref"] = rule["id"]
    extras.append(keep)

with open("existing_custom_rules.auto.tfvars.json", "w") as f:
    json.dump(
        {
            "zone_custom_firewall_ruleset_id": ruleset_id,
            "zone_custom_firewall_name": name,
            "zone_custom_firewall_extra_rules": extras,
        },
        f,
        indent=2,
    )
    f.write("\n")
print("wrote existing_custom_rules.auto.tfvars.json")
PY

if ! grep -q 'zone_custom_firewall_ruleset_id' terraform.tfvars 2>/dev/null; then
  RID="$(python3 -c 'import json; print(json.load(open("existing_custom_rules.auto.tfvars.json"))["zone_custom_firewall_ruleset_id"])')"
  printf '\nzone_custom_firewall_ruleset_id = "%s"\n' "$RID" >> terraform.tfvars
  echo "appended zone_custom_firewall_ruleset_id to terraform.tfvars"
fi
