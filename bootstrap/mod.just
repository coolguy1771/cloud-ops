set default-list
set quiet
set shell := ['bash', '-euo', 'pipefail', '-c']

bootstrap_dir := source_directory()
kubernetes_dir := bootstrap_dir + '/../kubernetes'

[confirm('Bootstrap cluster? [y|N]')]
[doc('Bootstrap a Kubernetes cluster for Flux (Omni/Terraform must already exist)')]
cluster: api-ready base apps

[doc('Apply Kubernetes namespaces')]
namespaces:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    find "{{ kubernetes_dir }}/apps" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r dir; do \
        if ! kustomize build "$dir" | yq ea -e 'select(.kind == "Namespace")' | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then \
            just log fatal "Failed to apply namespace" "stage" "{{ recipe_name() }}" "namespace" "$(basename "$dir")"; \
        fi; \
    done

[private]
base: api-ready nodes-ready namespaces
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kustomize build "{{ bootstrap_dir }}/kustomize/cloud-ops" | just template - | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then \
        just log fatal "Failed to apply bootstrap secrets" "stage" "{{ recipe_name() }}"; \
    fi
    if ! helmfile -f "{{ bootstrap_dir }}/helmfile/crds.yaml" template -q | yq ea -e 'select(.kind == "CustomResourceDefinition")' | kubectl apply --server-side --field-manager bootstrap --force-conflicts -f -; then \
        just log fatal "Failed to apply crds" "stage" "{{ recipe_name() }}"; \
    fi

[doc('Apply Helmfile platform apps')]
apps:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! helmfile -f "{{ bootstrap_dir }}/helmfile/apps.yaml" sync --hide-notes; then \
        just log fatal "Failed to sync helmfile" "stage" "{{ recipe_name() }}"; \
    fi

# Legacy entrypoint: same stages as `cluster` without confirmation.
[doc('Run all bootstrap stages (namespaces, base, apps)')]
all: namespaces base apps

[private]
api-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    until kubectl get --raw=/readyz &>/dev/null; do \
        just log info "Waiting for kube-apiserver. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"; \
        sleep 5; \
    done

[private]
nodes-ready:
    just log info "Running stage..." "stage" "{{ recipe_name() }}"
    if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then \
        until kubectl get nodes -o jsonpath='{.items[*].metadata.name}' | grep -q .; do \
            just log info "Waiting for nodes to register. Retrying in 5 seconds..." "stage" "{{ recipe_name() }}"; \
            sleep 5; \
        done \
    fi
