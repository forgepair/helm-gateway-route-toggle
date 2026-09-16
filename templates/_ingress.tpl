{{/*
gateway-route-toggle.ingress -- renders a networking.k8s.io/v1 Ingress from
the shared .Values.routing schema. Call from a consuming chart's own
templates/ingress.yaml as:

    {{- include "gateway-route-toggle.ingress" . }}

Consuming chart must provide (see README.md for the full schema):
  .Values.ingress.enabled     (bool, this template renders nothing if false)
  .Values.ingress.className   (optional)
  .Values.ingress.annotations (optional map)
  .Values.ingress.tls         (optional list)
  .Values.routing.host
  .Values.routing.paths[]     (path, pathType, serviceName, servicePort)
*/}}
{{- define "gateway-route-toggle.ingress" -}}
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ .Release.Name }}-route
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  {{- with .Values.ingress.tls }}
  tls:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  rules:
    - host: {{ .Values.routing.host }}
      http:
        paths:
          {{- range .Values.routing.paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ .serviceName }}
                port:
                  number: {{ .servicePort }}
          {{- end }}
{{- end }}
{{- end -}}
