{{- define "pluribusai.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "pluribusai.fullname" -}}
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

{{- define "pluribusai.labels" -}}
helm.sh/chart: {{ include "pluribusai.name" . }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ include "pluribusai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "pluribusai.selectorLabels" -}}
app.kubernetes.io/name: {{ include "pluribusai.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "pluribusai.secretName" -}}
{{- default (include "pluribusai.fullname" .) .Values.auth.existingSecret }}
{{- end }}

{{- define "pluribusai.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "pluribusai.fullname" .) }}
{{- end }}

{{- define "pluribusai.useBundledPostgres" -}}
{{- if and (eq .Values.store.type "postgres") (not .Values.externalDatabase.host) .Values.postgresql.enabled }}true{{- end }}
{{- end }}

{{- define "pluribusai.useExternalPostgres" -}}
{{- if and (eq .Values.store.type "postgres") .Values.externalDatabase.host }}true{{- end }}
{{- end }}

{{- define "pluribusai.postgresPassword" -}}
{{- .Values.externalDatabase.password | default .Values.postgresql.auth.password | default "changeme" }}
{{- end }}

{{- define "pluribusai.pgHost" -}}
{{- if eq (include "pluribusai.useExternalPostgres" .) "true" -}}
{{- .Values.externalDatabase.host -}}
{{- else if eq (include "pluribusai.useBundledPostgres" .) "true" -}}
{{- include "pluribusai.postgresql.fullname" . -}}
{{- end -}}
{{- end }}