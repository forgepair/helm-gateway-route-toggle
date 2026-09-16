# gateway-route-toggle

A Helm library chart that lets a chart author define HTTP routing **once**,
in a vendor-neutral schema, and render either a legacy
`networking.k8s.io/v1 Ingress` or a Gateway API `HTTPRoute` (or both, for a
migration period) from that single source.

## Why

`ingress-nginx`, the most widely deployed Ingress controller in the
Kubernetes ecosystem, was retired by its maintainers (hard EOL
2026-03-31), forcing an ecosystem-wide migration to the Gateway API. Every
chart maintainer supporting both mechanisms during the transition
currently hand-rolls a second, parallel `HTTPRoute` template next to their
existing `Ingress` template -- translating path types and backends by
hand, per chart, with no shared library. See `BRIEF.md` for the full case,
including live GitHub evidence of 10+ independently-maintained charts
solving this exact problem separately (mlflow, litellm, grafana, bitnami,
microcks, fleetdm, and others).

## Status

Proof-of-mechanism verified, converted to a real Helm library chart
(`type: library`) with a working example consumer. **Not yet published**
to any Helm repo / OCI registry. Scope is deliberately minimal -- see
below.

## Scope (what this does and does not support)

Supports:
- A single shared `routing` schema (host + an ordered list of
  path/pathType/serviceName/servicePort entries).
- Rendering `Ingress`, `HTTPRoute`, or both simultaneously (dual-write
  migration mode) from that one schema.
- `pathType` translation: `Prefix` -> `PathPrefix`, `Exact` -> `Exact`.
  Any other value (e.g. `ImplementationSpecific`, a legal `Ingress`
  pathType with no Gateway API equivalent) **fails loudly** at
  `helm template` time rather than silently rendering an invalid
  `HTTPRoute` that only breaks once applied to a real cluster.

Does **not** yet support (explicitly out of scope for v0.1.0, tracked as
follow-up work, not silently missing):
- Header/query-param match translation.
- TLS / cert-manager annotation mapping (Ingress and Gateway API express
  TLS very differently -- HTTPRoute's TLS config typically lives on the
  `Gateway` resource, not the route itself, which this library doesn't
  own).
- Weighted / multi-backend (canary) routing.

These are deliberately deferred rather than attempted partially: Ingress
expresses all three via controller-specific annotation dialects (nginx's
differs from Traefik's, etc.), so "translate Ingress" isn't one mapping,
it's effectively N mappings. Scoping this out keeps v0.1.0 correct and
honest about what it covers -- most of the real-world feature requests
this brief surveyed asked for exactly the path/host routing this chart
already provides, not annotation-level parity.

## Using it in your chart

1. Add it as a dependency in your chart's `Chart.yaml`:

   ```yaml
   dependencies:
     - name: gateway-route-toggle
       version: "0.1.0"
       repository: "file://../path/to/gateway-route-toggle"  # or an OCI repo once published
   ```

   Run `helm dependency update` to vendor it into your chart's `charts/`
   directory.

2. Add the shared schema to your chart's own `values.yaml` (see
   `values.schema.json` for the full shape, and
   `examples/consumer/values.yaml` for a complete working example):

   ```yaml
   routing:
     host: app.example.com
     paths:
       - path: /
         pathType: Prefix
         serviceName: app-svc
         servicePort: 80

   ingress:
     enabled: false
     className: nginx

   httpRoute:
     enabled: false
     parentRefs:
       - name: my-gateway
         namespace: gateway-system
   ```

3. Call the named templates from your own chart's templates:

   ```yaml
   # templates/ingress.yaml
   {{- include "gateway-route-toggle.ingress" . }}
   ```

   ```yaml
   # templates/httproute.yaml
   {{- include "gateway-route-toggle.httproute" . }}
   ```

That's the entire integration surface -- see `examples/consumer/` for a
complete, runnable chart doing exactly this, which is what this repo's own
verification is run against (there's no release to `helm template` a bare
library chart against on its own).

## Verifying it yourself

```
cd examples/consumer
helm dependency update .
helm template test . --set ingress.enabled=true --set httpRoute.enabled=false
helm template test . --set ingress.enabled=false --set httpRoute.enabled=true
helm template test . -f bad-values.yaml   # demonstrates the guard: exits 1
```

## Compatibility contract

Since this is meant to be imported by other charts, the following is the
public API and will follow SemVer from v0.1.0 onward:
- Named template names: `gateway-route-toggle.ingress`,
  `gateway-route-toggle.httproute`, `gateway-route-toggle.gatewayPathType`.
- The `routing` / `ingress` / `httpRoute` values schema (see
  `values.schema.json`).

## Not yet done

- **Cluster-side verification.** Everything above confirms the rendered
  YAML is well-formed and matches the intended shape. Nobody has yet
  applied a rendered `HTTPRoute` against a real Gateway API implementation
  (Envoy Gateway / istio / cilium) to confirm the API server actually
  accepts it (`status.parents[].conditions` reporting `Accepted: True`).
  Blocked on this machine not having Docker/a container runtime installed
  for a local `kind`/`k3d` cluster -- see `BRIEF.md`'s status notes.
- Packaging/publishing to an OCI registry or Helm repo index.

See `BRIEF.md` for the original pitch, demand evidence, and verification
history.
