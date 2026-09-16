{{/*
gateway-route-toggle.httproute -- renders a gateway.networking.k8s.io/v1
HTTPRoute from the SAME shared .Values.routing schema used by
gateway-route-toggle.ingress. Call from a consuming chart's own
templates/httproute.yaml as:

    {{- include "gateway-route-toggle.httproute" . }}

Consuming chart must provide (see README.md for the full schema):
  .Values.httpRoute.enabled     (bool, this template renders nothing if false)
  .Values.httpRoute.parentRefs  (list, passed through to spec.parentRefs)
  .Values.routing.host
  .Values.routing.paths[]       (path, pathType, serviceName, servicePort)

pathType is translated via gateway-route-toggle.gatewayPathType (see
_helpers.tpl) -- currently supports Prefix/Exact only. Header/query-param
matching, TLS/cert-manager annotation mapping, and weighted multi-backend
routing are explicitly NOT yet supported (see README.md's Scope section).
*/}}
{{- define "gateway-route-toggle.httproute" -}}
{{- if .Values.httpRoute.enabled }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ .Release.Name }}-route
spec:
  parentRefs:
    {{- toYaml .Values.httpRoute.parentRefs | nindent 4 }}
  hostnames:
    - {{ .Values.routing.host }}
  rules:
    {{- range .Values.routing.paths }}
    - matches:
        - path:
            type: {{ include "gateway-route-toggle.gatewayPathType" . }}
            value: {{ .path }}
      backendRefs:
        - name: {{ .serviceName }}
          port: {{ .servicePort }}
    {{- end }}
{{- end }}
{{- end -}}
