{{/*
Expand the chart name.
*/}}
{{- define "microservice.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Create a fully qualified app name: <release>-<name>
*/}}
{{- define "microservice.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "microservice.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "microservice.labels" -}}
app.kubernetes.io/name: {{ include "microservice.name" . }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Selector labels (stable across versions)
*/}}
{{- define "microservice.selectorLabels" -}}
app.kubernetes.io/name: {{ include "microservice.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

