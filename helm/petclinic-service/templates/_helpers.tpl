{{- define "petclinic-service.name" -}}
{{- .Values.name | default .Release.Name -}}
{{- end -}}

{{- define "petclinic-service.fullname" -}}
{{- .Values.name | default .Release.Name -}}
{{- end -}}

{{- define "petclinic-service.labels" -}}
app.kubernetes.io/name: {{ .Values.name | default .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/part-of: petclinic
{{- end -}}

{{- define "petclinic-service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Values.name | default .Release.Name }}
app.kubernetes.io/component: {{ .Values.component | default "service" }}
{{- end -}}

{{- define "petclinic-service.image" -}}
{{- .Values.image.repository }}:{{ .Values.image.tag | default "latest" -}}
{{- end -}}