{{/*
Expand the name of the chart.
*/}}
{{- define "go-auth.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "go-auth.fullname" -}}
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
{{- define "go-auth.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "go-auth.labels" -}}
helm.sh/chart: {{ include "go-auth.chart" . }}
{{ include "go-auth.selectorLabels" . }}
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
{{- define "go-auth.selectorLabels" -}}
app.kubernetes.io/name: {{ include "go-auth.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "go-auth.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "go-auth.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the image tag to use
*/}}
{{- define "go-auth.imageTag" -}}
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
Get the namespace
*/}}
{{- define "go-auth.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Logging configuration
*/}}
{{- define "go-auth.loggingConfig" -}}
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
