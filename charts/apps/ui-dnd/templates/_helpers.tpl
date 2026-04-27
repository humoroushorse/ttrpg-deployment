{{/*
Expand the name of the chart.
*/}}
{{- define "ui-dnd.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ui-dnd.fullname" -}}
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
{{- define "ui-dnd.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ui-dnd.labels" -}}
helm.sh/chart: {{ include "ui-dnd.chart" . }}
{{ include "ui-dnd.selectorLabels" . }}
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
{{- define "ui-dnd.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ui-dnd.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ui-dnd.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ui-dnd.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the image tag to use
*/}}
{{- define "ui-dnd.imageTag" -}}
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
{{- define "ui-dnd.namespace" -}}
{{- .Release.Namespace }}
{{- end }}
