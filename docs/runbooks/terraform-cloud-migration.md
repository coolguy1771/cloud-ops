# Migrate cloud-ops state to HCP Terraform

The configuration uses HCP Terraform organization `home-ops`, project
`cloud-ops`, and workspace `cloud-ops`. Keep the workspace execution mode set
to **Local**: this configuration discovers Omni machines and applies Omni COSI
resources with local `omnictl` commands.

## Preconditions

1. Create the `cloud-ops` project and `cloud-ops` workspace in HCP Terraform.
2. Set the workspace execution mode to **Local**.
3. Verify `omnictl` Kubernetes and Talos proxy access independently of the
   public Hetzner load balancer.
4. Run from the checkout that owns the current local Terraform state.

## Migrate and verify

```bash
cd infrastructure/terraform
terraform login
terraform state pull >"terraform-state-backup-$(date +%Y%m%dT%H%M%S).json"
terraform state list | sort >local-state-resources.txt
terraform init -migrate-state
terraform state list | sort >hcp-state-resources.txt
diff -u local-state-resources.txt hcp-state-resources.txt
terraform plan -out=tfplan
terraform show tfplan
```

Stop if the resource lists differ or the plan contains any unexpected create,
replace, or destroy action. The intended first plan only enables server/load
balancer protection, disables the API load balancer public interface, and
restricts API, Talos, and NodePort firewall sources to the private network.

Verify Omni proxy access again immediately before applying. Apply only after a
separate review and approval:

```bash
terraform apply tfplan
```

After apply, verify Omni Kubernetes and Talos access again. If either path
fails, restore the public interface/firewall settings through Hetzner Cloud,
then correct Terraform and generate a new reviewed plan.
