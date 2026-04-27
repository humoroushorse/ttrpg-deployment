{{/*
Expand the name of the chart.
*/}}
{{- define "ttrpg-umbrella.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ttrpg-umbrella.fullname" -}}
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
{{- define "ttrpg-umbrella.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ttrpg-umbrella.labels" -}}
helm.sh/chart: {{ include "ttrpg-umbrella.chart" . }}
{{ include "ttrpg-umbrella.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ttrpg-umbrella.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ttrpg-umbrella.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Get the application namespace
*/}}
{{- define "ttrpg-umbrella.namespace" -}}
{{- printf "ttrpg-%s" (.Values.environment | default "local") }}
{{- end }}

{{/*
Get the vault namespace
*/}}
{{- define "ttrpg-umbrella.vaultNamespace" -}}
vault
{{- end }}

{{/*
Import shared validation helpers
*/}}
{{- define "app.validateVersion" -}}
{{- $version := . -}}
{{- if not $version -}}
{{- "latest" -}}
{{- else -}}
{{- $specialTags := list "latest" "dev" "staging" "main" "master" -}}
{{- if has $version $specialTags -}}
{{- $version -}}
{{- else if regexMatch "^v?[0-9]+\\.[0-9]+\\.[0-9]+(-[a-zA-Z0-9.-]+)?(\\+[a-zA-Z0-9.-]+)?$" $version -}}
{{- $version -}}
{{- else -}}
{{- fail (printf "Invalid version format: %s. Must be semantic version (vX.Y.Z or X.Y.Z) or special tag (latest, dev, staging)" $version) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Get the image tag with precedence
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
