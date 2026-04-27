{{/*
Expand the name of the chart.
*/}}
{{- define "ingress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "ingress.fullname" -}}
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
{{- define "ingress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ingress.labels" -}}
helm.sh/chart: {{ include "ingress.chart" . }}
{{ include "ingress.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ingress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ingress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: ingress-controller
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ingress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ingress.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Namespace for resources
*/}}
{{- define "ingress.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Keycloak service URL
*/}}
{{- define "ingress.keycloakUrl" -}}
{{- printf "http://keycloak.ttrpg-%s.svc.cluster.local:8080" .Values.environment }}
{{- end }}
