{{/*
PodDisruptionBudget template for stateless applications
Usage: {{ include "shared.podDisruptionBudget" (dict "name" "app-name" "namespace" "namespace" "replicas" 3 "enabled" true "labels" .Labels) }}
*/}}
{{- define "shared.podDisruptionBudget" -}}
{{- if .enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .name }}-pdb
  namespace: {{ .namespace }}
  labels:
    {{- toYaml .labels | nindent 4 }}
spec:
  {{- if eq (.replicas | int) 1 }}
  minAvailable: 1
  {{- else }}
  minAvailable: 50%
  {{- end }}
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .name }}
{{- end }}
{{- end }}
