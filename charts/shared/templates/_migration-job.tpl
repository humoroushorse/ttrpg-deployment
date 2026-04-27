{{/*
Migration Job Template
Generates a Kubernetes Job for running database migrations before application deployment.
This template is designed to be included by application charts.

Usage in application chart:
{{- include "shared.migrationJob" (dict "Chart" .Chart "Release" .Release "Values" .Values "migrationConfig" .Values.migration) }}

Required values in application chart:
  migration:
    enabled: true
    image:
      repository: "ghcr.io/your-org/app"
      tag: "latest"
    command: ["/app/migrate"]
    args: ["up"]
    env: []
    database:
      name: "mydb"
*/}}
{{- define "shared.migrationJob" -}}
{{- $config := .migrationConfig -}}
{{- if $config.enabled -}}
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "app.fullname" . }}-migration
  namespace: {{ include "app.namespace" . }}
  labels:
    {{- include "app.labels" . | nindent 4 }}
    app.kubernetes.io/component: migration
  annotations:
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-weight: "-5"
    helm.sh/hook-delete-policy: before-hook-creation
spec:
  # Retry up to 3 times on failure
  backoffLimit: {{ $config.backoffLimit | default 3 }}
  # Delete completed jobs after 24 hours
  ttlSecondsAfterFinished: {{ $config.ttlSecondsAfterFinished | default 86400 }}
  template:
    metadata:
      labels:
        {{- include "app.selectorLabels" . | nindent 8 }}
        app.kubernetes.io/component: migration
      annotations:
        {{- include "vault.annotations" . | nindent 8 }}
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "app.serviceAccountName" . }}
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: migration
        image: "{{ $config.image.repository }}:{{ $config.image.tag | default .Values.global.version | default "latest" }}"
        imagePullPolicy: {{ $config.image.pullPolicy | default "IfNotPresent" }}
        command:
          {{- toYaml $config.command | nindent 10 }}
        {{- if $config.args }}
        args:
          {{- toYaml $config.args | nindent 10 }}
        {{- end }}
        env:
        - name: DATABASE_NAME
          value: {{ $config.database.name | quote }}
        {{- with $config.env }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        volumeMounts:
        - name: tmp
          mountPath: /tmp
        {{- with $config.volumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        resources:
          {{- toYaml ($config.resources | default (dict "requests" (dict "cpu" "100m" "memory" "128Mi") "limits" (dict "cpu" "500m" "memory" "256Mi"))) | nindent 10 }}
      volumes:
      - name: tmp
        emptyDir: {}
      {{- with $config.volumes }}
      {{- toYaml . | nindent 6 }}
      {{- end }}
{{- end -}}
{{- end -}}
