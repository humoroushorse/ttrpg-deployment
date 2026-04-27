{{/*
Expand the name of the chart.
*/}}
{{- define "app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "app.labels" -}}
helm.sh/chart: {{ include "app.chart" . }}
{{ include "app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ttrpg
environment: {{ .Values.environment | default "local" }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the image tag to use
Precedence: .Values.image.tag > .Values.version > .Values.global.version > "latest"
*/}}
{{- define "app.imageTag" -}}
{{- if .Values.image.tag }}
{{- .Values.image.tag }}
{{- else if .Values.version }}
{{- .Values.version }}
{{- else if .Values.global.version }}
{{- .Values.global.version }}
{{- else }}
{{- "latest" }}
{{- end }}
{{- end }}

{{/*
Validate semantic version format
Accepts: vX.Y.Z, X.Y.Z, or special tags (latest, dev, staging)
Returns: the version if valid, fails if invalid
*/}}
{{- define "app.validateVersion" -}}
{{- $version := . -}}
{{- $specialTags := list "latest" "dev" "staging" "main" "master" -}}
{{- if has $version $specialTags -}}
{{- $version -}}
{{- else if regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9.-]+)?(\\+[a-zA-Z0-9.-]+)?$" $version -}}
{{- $version -}}
{{- else -}}
{{- fail (printf "Invalid version format: %s. Must be semantic version (vX.Y.Z or X.Y.Z) or special tag (latest, dev, staging)" $version) -}}
{{- end -}}
{{- end }}

{{/*
Get and validate the image tag
This combines imageTag retrieval with validation
*/}}
{{- define "app.validatedImageTag" -}}
{{- $tag := include "app.imageTag" . -}}
{{- include "app.validateVersion" $tag -}}
{{- end }}

{{/*
Get the namespace for the application
*/}}
{{- define "app.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Logging configuration environment variables
Generates logging configuration based on global logging settings
*/}}
{{- define "app.loggingConfig" -}}
{{- $global := .Values.global | default dict -}}
{{- $globalLogging := $global.logging | default dict -}}
{{- $logging := .Values.logging | default $globalLogging -}}
{{- $structuredLogging := $logging.structuredLogging | default dict -}}
{{- $logLevel := index ($logging.level | default dict) (.Values.environment | default "local") | default "info" -}}
LOG_FORMAT: {{ $logging.format | default "json" | quote }}
LOG_LEVEL: {{ $logLevel | lower | quote }}
LOG_STRUCTURED: {{ $structuredLogging.enabled | default true | quote }}
LOG_INCLUDE_TIMESTAMP: {{ $structuredLogging.includeTimestamp | default true | quote }}
LOG_INCLUDE_SERVICE: {{ $structuredLogging.includeService | default true | quote }}
LOG_INCLUDE_ENVIRONMENT: {{ $structuredLogging.includeEnvironment | default true | quote }}
LOG_INCLUDE_TRACE_ID: {{ $structuredLogging.includeTraceId | default true | quote }}
{{- end }}

{{/*
Vault annotations for injecting database credentials
Generates Vault agent annotations for sidecar injection
*/}}
{{- define "vault.annotations" -}}
{{- $global := .Values.global | default dict -}}
{{- $vault := $global.vault | default dict -}}
{{- if $vault.enabled | default true }}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ include "app.name" . | quote }}
vault.hashicorp.com/agent-inject-secret-database: "database/creds/{{ include "app.name" . }}-role"
vault.hashicorp.com/agent-inject-template-database: |
  {{`{{- with secret "database/creds/`}}{{ include "app.name" . }}{{`-role" -}}
  export POSTGRES_USER="{{ .Data.username }}"
  export POSTGRES_PASSWORD="{{ .Data.password }}"
  {{- end }}`}}
{{- end }}
{{- end }}
