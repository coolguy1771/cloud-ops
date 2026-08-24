#!/usr/bin/env -S just --justfile

set default-list
set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

mod bootstrap "bootstrap"
mod kube "kubernetes"

[private]
log lvl msg *args:
    gum log -t rfc3339 -s -l "{{ lvl }}" "{{ msg }}" {{ args }}

# Render Jinja templates and inject 1Password secret references.
# Pass `-` to read template from stdin (used by kustomize build | just template -).
#
# The trailing yq pass re-quotes stringData values: kustomize build's YAML
# writer drops quotes it considers unnecessary on plain scalars (e.g. around
# an `op://...` reference), so a numeric-looking secret value substituted in
# by `op inject` comes out as an unquoted YAML number — which kubectl then
# rejects, since Secret stringData values must be strings.
[private]
template file *args:
    minijinja-cli "{{ file }}" {{ args }} | op inject | yq eval 'with(select(.stringData); .stringData[] |= (. | tostring))'