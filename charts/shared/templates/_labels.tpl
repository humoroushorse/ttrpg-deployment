{{/*
Generate standardized kebab-case labels
Usage: {{ include "labels.standard" . }}
*/}}
{{- define "labels.standard" -}}
{{- include "app.labels" . }}
project: ttrpg
{{- if .Values.labels }}
{{- range $key, $value := .Values.labels }}
{{ $key | kebabcase }}: {{ $value | kebabcase | quote }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Generate kebab-case resource name
Usage: {{ include "labels.resourceName" "MyResourceName" }}
*/}}
{{- define "labels.resourceName" -}}
{{- . | lower | replace "_" "-" | replace " " "-" }}
{{- end }}

{{/*
Generate environment-specific labels
Usage: {{ include "labels.environment" . }}
*/}}
{{- define "labels.environment" -}}
environment: {{ .Values.environment | default "local" | kebabcase }}
deployment-type: {{ .Values.deploymentType | default "standard" | kebabcase }}
{{- end }}

{{/*
Generate component labels
Usage: {{ include "labels.component" "backend" }}
*/}}
{{- define "labels.component" -}}
component: {{ . | kebabcase }}
{{- end }}

{{/*
Generate tier labels
Usage: {{ include "labels.tier" "application" }}
*/}}
{{- define "labels.tier" -}}
tier: {{ . | kebabcase }}
{{- end }}

{{/*
Validate kebab-case format
Returns error if string doesn't match kebab-case pattern
Usage: {{ include "labels.validateKebabCase" "my-resource-name" }}
*/}}
{{- define "labels.validateKebabCase" -}}
{{- if not (regexMatch "^[a-z0-9]+(-[a-z0-9]+)*$" .) }}
{{- fail (printf "Invalid kebab-case format: %s. Must be lowercase alphanumeric with hyphens only." .) }}
{{- end }}
{{- end }}
