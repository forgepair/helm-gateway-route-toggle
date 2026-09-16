{{/*
Translate the chart's vendor-neutral pathType into the Gateway API's
HTTPRoute path-match type vocabulary. This is the exact mechanical
translation step every hand-rolled retrofit PR in the chase (mlflow #25433,
litellm #41193, etc.) reimplements ad hoc, one chart at a time.

Fails loudly (helm template exit 1) on a pathType with no Gateway API
equivalent (e.g. ImplementationSpecific), rather than passing it through
into a syntactically valid but semantically invalid HTTPRoute that only
breaks once applied to a real cluster.
*/}}
{{- define "gateway-route-toggle.gatewayPathType" -}}
{{- if eq .pathType "Prefix" -}}
PathPrefix
{{- else if eq .pathType "Exact" -}}
Exact
{{- else -}}
{{- fail (printf "unsupported pathType %q: HTTPRoute only supports Prefix or Exact translation" .pathType) -}}
{{- end -}}
{{- end -}}
