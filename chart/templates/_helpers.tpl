{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name of the chart.
*/}}
{{- define "chart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "vault.annotations" -}}
vault.hashicorp.com/agent-inject: "true"
vault.hashicorp.com/agent-init-first: "true"
vault.hashicorp.com/agent-pre-populate-only: "true"
vault.hashicorp.com/role: "{{ .Values.global.vault.role }}"
vault.hashicorp.com/agent-inject-secret-config: "{{ .Values.global.vault.path }}"
vault.hashicorp.com/agent-requests-mem: ""
vault.hashicorp.com/agent-requests-cpu: ""
vault.hashicorp.com/agent-limits-mem: ""
vault.hashicorp.com/agent-limits-cpu: ""
vault.hashicorp.com/agent-inject-template-config: |
    {{ "{{" }} with secret "{{ .Values.global.vault.path }}" {{ "}}" }}
    {{ "{{" }} range $k, $v := .Data.data {{ "}}" }}
        export {{"{{"}} $k {{"}}"}}={{"{{"}} $v {{"}}"}}
    {{ "{{-" }} end {{ "}}" }}
    {{ "{{-" }} end {{ "}}" }}
{{- end -}}


{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "chart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}
