{{/*
Deployment strategy template for zero-downtime rolling updates
Usage: {{ include "shared.deploymentStrategy" . }}
*/}}
{{- define "shared.deploymentStrategy" -}}
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1
    maxUnavailable: 0
{{- end }}
