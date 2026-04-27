{{/*
Vault Agent Injector annotations for database credentials
Usage: {{ include "vault.annotations" . }}
*/}}
{{- define "vault.annotations" -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ include "app.name" . | quote }}
vault.hashicorp.com/agent-inject-secret-database: {{ printf "%s/database/creds/%s-role" (.Values.environment | default "local") (include "app.name" .) | quote }}
vault.hashicorp.com/agent-inject-template-database: |
  {{`{{- with secret `}}{{ printf "\"%s/database/creds/%s-role\"" (.Values.environment | default "local") (include "app.name" .) }}{{` -}}`}}
  export POSTGRES_USER="{{`{{ .Data.username }}`}}"
  export POSTGRES_PASSWORD="{{`{{ .Data.password }}`}}"
  export POSTGRES_HOST="{{ include "app.fullname" . }}-postgresql.{{ include "app.namespace" . }}.svc.cluster.local"
  export POSTGRES_PORT="5432"
  export POSTGRES_DB="{{ .Values.database.name | default (include "app.name" .) }}"
  {{`{{- end }}`}}
{{- end }}

{{/*
Vault Agent Injector annotations for custom secrets
Usage: {{ include "vault.customAnnotations" (dict "context" . "secretPath" "path/to/secret" "secretName" "my-secret") }}
*/}}
{{- define "vault.customAnnotations" -}}
{{- $ctx := .context }}
{{- $secretPath := .secretPath }}
{{- $secretName := .secretName }}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: {{ include "app.name" $ctx | quote }}
vault.hashicorp.com/agent-inject-secret-{{ $secretName }}: {{ printf "%s/%s" ($ctx.Values.environment | default "local") $secretPath | quote }}
{{- end }}

{{/*
Vault Agent Injector annotations for Keycloak admin credentials
Usage: {{ include "vault.keycloakAnnotations" . }}
*/}}
{{- define "vault.keycloakAnnotations" -}}
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

{{/*
Vault Agent Injector annotations for Cloudflare Tunnel
Usage: {{ include "vault.cloudflareAnnotations" . }}
*/}}
{{- define "vault.cloudflareAnnotations" -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "cloudflare"
vault.hashicorp.com/agent-inject-secret-tunnel: {{ printf "%s/cloudflare/tunnel" (.Values.environment | default "local") | quote }}
vault.hashicorp.com/agent-inject-template-tunnel: |
  {{`{{- with secret `}}{{ printf "\"%s/cloudflare/tunnel\"" (.Values.environment | default "local") }}{{` -}}`}}
  {{`{{ .Data.credentials | toJSON }}`}}
  {{`{{- end }}`}}
{{- end }}

{{/*
Vault Agent Injector annotations for PostgreSQL root credentials
Usage: {{ include "vault.postgresRootAnnotations" . }}
*/}}
{{- define "vault.postgresRootAnnotations" -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/role: "postgresql"
vault.hashicorp.com/agent-inject-secret-root: {{ printf "%s/postgres-root/creds" (.Values.environment | default "local") | quote }}
vault.hashicorp.com/agent-inject-template-root: |
  {{`{{- with secret `}}{{ printf "\"%s/postgres-root/creds\"" (.Values.environment | default "local") }}{{` -}}`}}
  {{`{{ .Data.password }}`}}
  {{`{{- end }}`}}
{{- end }}
