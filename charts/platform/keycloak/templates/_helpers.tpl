{{/*
Expand the name of the chart.
*/}}
{{- define "keycloak.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "keycloak.fullname" -}}
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
{{- define "keycloak.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "keycloak.labels" -}}
helm.sh/chart: {{ include "keycloak.chart" . }}
{{ include "keycloak.selectorLabels" . }}
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
{{- define "keycloak.selectorLabels" -}}
app.kubernetes.io/name: {{ include "keycloak.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "keycloak.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "keycloak.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the namespace for the deployment
*/}}
{{- define "keycloak.namespace" -}}
{{- .Release.Namespace }}
{{- end }}

{{/*
Get the database host
*/}}
{{- define "keycloak.databaseHost" -}}
{{- if .Values.database.host }}
{{- .Values.database.host }}
{{- else }}
{{- printf "platform-postgresql.%s.svc.cluster.local" .Release.Namespace }}
{{- end }}
{{- end }}


{{/*
Vault Agent Injector annotations for Keycloak admin and database credentials.
Only emits annotations when vault.enabled is true.
*/}}
{{- define "vault.keycloakAnnotations" -}}
{{- $vault := .Values.vault | default dict -}}
{{- if $vault.enabled }}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "keycloak"
vault.hashicorp.com/agent-inject-secret-admin: {{ printf "%s/keycloak/admin" (.Values.environment | default "local") | quote }}
vault.hashicorp.com/agent-inject-template-admin: |
  {{`{{- with secret `}}{{ printf "\"%s/keycloak/admin\"" (.Values.environment | default "local") }}{{` -}}`}}
  export KEYCLOAK_ADMIN="{{`{{ .Data.username }}`}}"
  export KEYCLOAK_ADMIN_PASSWORD="{{`{{ .Data.password }}`}}"
  {{`{{- end }}`}}
vault.hashicorp.com/agent-inject-secret-database: {{ printf "%s/database/creds/keycloak-role" (.Values.environment | default "local") | quote }}
vault.hashicorp.com/agent-inject-template-database: |
  {{`{{- with secret `}}{{ printf "\"%s/database/creds/keycloak-role\"" (.Values.environment | default "local") }}{{` -}}`}}
  export DB_USERNAME="{{`{{ .Data.username }}`}}"
  export DB_PASSWORD="{{`{{ .Data.password }}`}}"
  {{`{{- end }}`}}
{{- end }}
{{- end }}
