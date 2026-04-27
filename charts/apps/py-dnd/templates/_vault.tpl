{{/*
Vault Agent Injector annotations for database credentials.
Only emits annotations when vault.enabled is true in values.
*/}}
{{- define "py-dnd.vaultAnnotations" -}}
{{- $vault := .Values.vault | default dict -}}
{{- if $vault.enabled }}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ include "py-dnd.name" . | quote }}
vault.hashicorp.com/agent-inject-secret-database: {{ printf "database/creds/%s-role" (include "py-dnd.name" .) | quote }}
vault.hashicorp.com/agent-inject-template-database: |
  {{`{{- with secret `}}{{ printf "\"database/creds/%s-role\"" (include "py-dnd.name" .) }}{{` -}}`}}
  export POSTGRES_MASTER_USER="{{`{{ .Data.username }}`}}"
  export POSTGRES_MASTER_PASSWORD="{{`{{ .Data.password }}`}}"
  {{`{{- end }}`}}
{{- end }}
{{- end }}

{{/*
Logging configuration environment variables
*/}}
{{- define "py-dnd.loggingConfig" -}}
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
