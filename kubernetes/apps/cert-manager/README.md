# cert-manager

Automated TLS certificate management using Let's Encrypt.

## Overview

cert-manager automates the issuance and renewal of TLS certificates from Let's Encrypt using the ACME protocol. This setup uses HTTP-01 challenge validation via Envoy Gateway.

## Components

- **cert-manager**: Core controller for certificate management
- **webhook**: Validates certificate resources
- **cainjector**: Injects CA bundles into webhooks and API services

## ClusterIssuers

### letsencrypt-production

Production Let's Encrypt issuer for valid certificates.

**Challenge Type**: HTTP-01 via Gateway API
**Email**: admin@rackspace.example.com (update this!)
**Rate Limits**: [Let's Encrypt Production Limits](https://letsencrypt.org/docs/rate-limits/)

### letsencrypt-staging

Staging issuer for testing. Certificates are not trusted.

**Challenge Type**: HTTP-01 via Gateway API
**Email**: admin@rackspace.example.com (update this!)
**Rate Limits**: Much higher than production

## Automatic Certificate

A wildcard certificate for `*.rackspace.example.com` is automatically created in the `network` namespace as `tls-certificate`. This is used by the Envoy Gateway.

## Creating Certificates

### Via Gateway API (Recommended)

Certificates are automatically created when using Gateway API HTTPRoutes with TLS:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-production
spec:
  hostnames:
    - app.rackspace.example.com
  parentRefs:
    - name: envoy-external
      namespace: network
      sectionName: https
```

### Manual Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-cert
  namespace: my-namespace
spec:
  secretName: my-tls-secret
  issuerRef:
    name: letsencrypt-production
    kind: ClusterIssuer
  dnsNames:
    - app.rackspace.example.com
```

## Monitoring

Prometheus metrics are exposed on port 9402:

- `certmanager_certificate_ready_status`: Certificate readiness
- `certmanager_certificate_expiration_timestamp_seconds`: Certificate expiration time
- `certmanager_http_acme_client_request_duration_seconds`: ACME request duration

## Troubleshooting

### Check Certificate Status

```bash
kubectl get certificate -A
kubectl describe certificate <name> -n <namespace>
```

### Check ClusterIssuer Status

```bash
kubectl get clusterissuer
kubectl describe clusterissuer letsencrypt-production
```

### View cert-manager Logs

```bash
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

### Common Issues

**Certificate stuck in Pending**:
- Check that Envoy Gateway is running and accessible
- Verify DNS points to the LoadBalancer IP
- Check cert-manager logs for ACME challenge errors

**Rate limit exceeded**:
- Use `letsencrypt-staging` for testing
- Wait for rate limit window to reset (usually 1 week)

## Configuration

Key Helm values in `helmrelease.yaml`:

- `crds.enabled: true` - Install CRDs with Helm
- `dns01RecursiveNameservers` - Use DoH for DNS queries
- `prometheus.enabled` - Enable metrics export

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt](https://letsencrypt.org/)
- [Gateway API with cert-manager](https://gateway-api.sigs.k8s.io/guides/tls/)
