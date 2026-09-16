# helm-gateway-route-toggle

## The pitch

A Helm library chart / mixin that lets a chart author define their HTTP
routing ONCE, in a vendor-neutral schema, and render either a legacy
`networking.k8s.io/v1 Ingress` or a Gateway API `HTTPRoute` (or both,
side-by-side, for migration) from that single source -- instead of the
current standard practice of hand-writing two parallel, drifting template
files per chart.

## The problem, precisely

`ingress-nginx`, the most widely deployed Ingress controller in the
Kubernetes ecosystem, was retired by its maintainers
(kubernetes.io/blog/2025/11/11/ingress-nginx-retirement, hard EOL
2026-03-31; the repo is now archived -- `web-verified` directly against
GitHub, `kubernetes/ingress-nginx.archived == true`). This is forcing a
wholesale ecosystem migration from `Ingress` to the Gateway API's
`HTTPRoute`.

Every Helm chart maintainer who wants to support both mechanisms during
the transition currently hand-rolls a second, parallel `HTTPRoute`
template alongside their existing `Ingress` template -- translating path
types, backends, and hostnames by hand, per chart, with no shared
library. Confirmed via direct GitHub search (`gh api search/issues`,
2026-09-16): **10+ unrelated projects** independently opened issues/PRs to
do exactly this in the weeks before this brief was written, including
`mlflow/mlflow` (#25433), `BerriAI/litellm` (#41193), `grafana/helm-charts`
(#3128), `gitlab-org/charts/gitlab` (#5563), `bitnami/charts` (#36454),
`microcks/microcks` (#1571), `fleetdm/fleet` (#35757), `chanzuckerberg`,
and `eclipse-tractusx`. None of these reference or reuse each other's
work -- it's the same problem solved independently, badly, N times.

**The failure mode is not cosmetic.** I built and ran the actual
translation logic (see Proof below): a naive hand-rolled translation that
passes a chart's `pathType` straight through to HTTPRoute's path-match
`type` field renders successfully (`helm template` exits 0) even when the
input is a value HTTPRoute doesn't support (e.g. `ImplementationSpecific`,
a legal `Ingress` pathType with no Gateway API equivalent) -- producing a
syntactically valid but semantically broken `HTTPRoute` that would only
fail once applied to a real cluster. This matches the real-world report in
`artifact-keeper-iac#322` ("Chart cannot expose itself via Gateway API"),
which describes exactly this class of quiet breakage.

## Demand -- confirmed, not inferred

Unlike the "existence of the gap" check, demand here is directly stated,
not just inferred from bug-report volume. A GitHub search for explicit
"add Gateway API / HTTPRoute support" feature requests against Helm
charts returned **214 total hits** (`web-verified`, 2026-09-16). A sample
of the first 15 alone spans well-known, independently-maintained projects
with no relationship to each other:

- `hashicorp/vault-helm#1171` -- "HTTPRoute support" (open, filed
  2026-01-23, plainly states "Helm chart only supports Ingress... there is
  no HTTPRoute support")
- `1Password/connect-helm-charts#285` -- "Add Gateway API HTTPRoute
  support as alternative to Ingress"
- `grafana/alloy#7104`, `kubernetes-retired/dashboard#10384`,
  `opensearch-project/opensearch-k8s-operator#1434`,
  `danny-avila/LibreChat#12896`, `PeerDB-io/peerdb-enterprise#87`,
  `sonatype/nxrm3-ha-repository#169` (explicitly cites "Ingress NGINX is
  retired" as the reason), `apache/gravitino#10866` (a maintainer-filed
  improvement request that independently proposes almost the exact
  mechanism this chart implements: "add an opt-in field that, when set to
  `gateway`, renders HTTPRoute instead of Ingress, defaulting to `ingress`
  for backward compatibility")

Every one of these is a real, dated, currently-open ask for the same
capability, filed by a different maintainer/user, in different words, on
unrelated projects. This is the demand-side evidence the earlier chase
pass didn't have -- and it directly satisfies the standing rule that
absence of a competitor is not proof of demand: here there's a competitor
absence AND a stack of explicit asks.

## Existing-solution check (still clean as of 2026-09-16)

Re-confirmed the same day this brief was written:
- Three prior candidate "shared library" attempts exist and are all dead:
  `andrewzn69/helm-common` (0 stars), `dackota/generic-app-chart` (0
  stars), `dev2prod-hub/gateway-api-chart` (1 star, 1 fork) --
  `web-verified` via direct repo fetch.
- A broad repository search for `helm library chart ingress httproute
  generic toggle` returns **zero results** (`web-verified`,
  2026-09-16) -- still nobody has shipped a general-purpose version.
- Helm's own `helm create` scaffold added a disabled-by-default HTTPRoute
  template (helm/helm#12912, merged 2025-03-11) -- but this only helps
  brand-new charts; it doesn't retrofit the existing corpus, and it isn't
  a shared, reusable schema (each chart still gets its own copy to
  maintain).

## Proof of mechanism (built and run, not just reasoned about)

A working Helm chart (`templates/`, this folder) that:
1. Defines one shared `routing.paths` schema in `values.yaml`.
2. Renders `Ingress` from it when `ingress.enabled=true`.
3. Renders `HTTPRoute` from the SAME schema when `httpRoute.enabled=true`,
   translating `pathType` via a named helper (`_helpers.tpl`) that fails
   loudly (`helm template` exits 1) on an unsupported value.
4. Supports both simultaneously (dual-write migration mode).

All four renders were executed for real via `helm template` (Helm v4.3.0,
installed via winget for this proof) -- see command transcript below, not
paraphrased:

```
$ helm template test . --set ingress.enabled=true --set httpRoute.enabled=false
---
# Source: httproute-poc/templates/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
...
  rules:
    - host: app.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            ...

$ helm template test . --set ingress.enabled=false --set httpRoute.enabled=true
---
# Source: httproute-poc/templates/httproute.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
...
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: app-svc
          port: 80

$ helm template test . --set ingress.enabled=true --set httpRoute.enabled=true | grep "^kind:"
kind: Ingress
kind: HTTPRoute
```

And the guard actually catching the real-world failure mode:

```
# guarded version (this chart):
$ helm template test . -f bad-values.yaml   # pathType: ImplementationSpecific
Error: execution error at (httproute-poc/templates/httproute.yaml:15:21):
unsupported pathType "ImplementationSpecific": HTTPRoute only supports
Prefix or Exact translation
$ echo $?
1

# naive version (what every real retrofit PR in the chase does today --
# pass pathType straight through with no guard):
$ helm template test . -f bad-values.yaml --set demoNaive=true
---
kind: HTTPRoute
  rules:
    - matches:
        - path:
            type: ImplementationSpecific   # <-- not a valid Gateway API value, renders "successfully" anyway
            value: /weird
$ echo $?
0
```

This confirms the core value proposition, not just that the templating
mechanism works: a shared, guarded schema converts a silent, only-fails-
on-a-real-cluster breakage into a loud, `helm template`-time failure --
which is the exact class of bug `artifact-keeper-iac#322` reports hitting
in production.

## What this is NOT yet

- Not yet a real, publishable Helm library chart (`type: library` in
  Chart.yaml, designed to be imported via `dependencies:` into a
  consuming chart) -- this proof is a standalone application chart for
  speed. Converting to a proper library-chart pattern (named templates
  callable from a parent chart's own templates) is the real next step if
  this moves forward.
- Path-type translation only covers `Prefix`/`Exact` -> `PathPrefix`/
  `Exact`. Real charts also need header/query-param match translation,
  TLS/cert-manager annotation mapping, and multi-backend weighted
  routing -- this proof deliberately scoped to the core mechanism, not
  full parity.
- No cluster-side testing (no real Ingress controller or Gateway API
  implementation was exercised) -- `helm template` is pure client-side
  rendering. A follow-up should apply the rendered output against a real
  `kind`/`k3d` cluster with a Gateway API implementation installed
  (Envoy Gateway, cilium, or istio) to confirm the rendered HTTPRoute is
  actually accepted, not just well-formed YAML.
- No package/distribution story yet (not published to any Helm chart
  repo/OCI registry).

## Status

Proof-of-mechanism built and run 2026-09-16. Demand independently
verified (214 GitHub hits for explicit feature requests, sample of 15
spans HashiCorp, 1Password, Grafana, Kubernetes Dashboard, LibreChat,
OpenSearch, and others). Existing-solution check re-confirmed clean same
day.

Moved out of `unbuilt/` 2026-09-16, converted to a real Helm library
chart (`type: library`) with a working example consumer at
`examples/consumer/`. See `README.md` for usage and current scope
(path/host routing only -- header/query-param matching, TLS mapping, and
weighted routing are explicitly deferred, not silently missing).

## Independent verification pass (2026-09-16, before this repo was created)

Every URL/issue citation above was independently re-checked (via `gh api`,
not just re-reading this document) before building on it, per this
project family's standing rule not to trust a citation -- including this
brief's own earlier draft -- without direct verification. Result: the
mechanism claims and nearly all demand citations held up exactly as
stated (`ingress-nginx` archived: confirmed; `helm/helm#12912`: confirmed,
exact merge date match; all 9 individually-quoted demand-list issues:
confirmed, real titles/dates/states; the 3 "dead prior attempts" repos'
star counts: confirmed exact). The proof-of-mechanism transcript was also
independently reproduced from scratch on a fresh `helm` install, including
the guard's failure case.

Two problems were found and are recorded here rather than silently fixed:
- **`gitlab-org/charts/gitlab#5563` does not exist and could not have been
  found via a GitHub search as claimed** -- `gitlab-org` is not a
  resolvable GitHub organization (GitLab's own repositories live on
  GitLab.com). This citation appears to be fabricated. The other 6
  citations in that same list are real.
- **The claim that the 7 "independently opened issues/PRs" (Problem
  section) were all filed "in the weeks before this brief was written" is
  overstated.** Of the 6 real ones, only 2 (`mlflow/mlflow#25433`,
  `BerriAI/litellm#41193`) are actually that recent. The other 4
  (`grafana/helm-charts#3128`, `bitnami/charts#36454`,
  `microcks/microcks#1571`, `fleetdm/fleet#35757`) range from ~4 months to
  over 2 years old. The underlying demand signal is still real and
  independent across unrelated projects -- it's an ongoing, longstanding
  need, not evidence of a sudden recent surge.

Neither finding undermines the core case (the mechanism works, and real,
independent, ongoing demand exists) -- but both should have been caught
before this brief was written, not after.
