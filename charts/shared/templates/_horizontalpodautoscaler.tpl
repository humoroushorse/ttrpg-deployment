{{/*
HorizontalPodAutoscaler template for applications
Usage: {{ include "shared.horizontalPodAutoscaler" (dict "name" "app-name" "namespace" "namespace" "enabled" true "minReplicas" 2 "maxReplicas" 10 "targetCPU" 70 "targetMemory" 80 "labels" .Labels) }}
*/}}
{{- define "shared.horizontalPodAutoscaler" -}}
{{- if .enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ .name }}-hpa
  namespace: {{ .namespace }}
  labels:
    {{- toYaml .labels | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ .name }}
  minReplicas: {{ .minReplicas | default 2 }}
  maxReplicas: {{ .maxReplicas | default 10 }}
  metrics:
  {{- if .targetCPU }}
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .targetCPU }}
  {{- end }}
  {{- if .targetMemory }}
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: {{ .targetMemory }}
  {{- end }}
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
{{- end }}
{{- end }}
