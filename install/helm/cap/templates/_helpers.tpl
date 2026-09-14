{{- define "cap.image" -}}
{{- printf "%s/%s:%s" .Values.global.registry .image .tag -}}
{{- end -}}

{{- define "cap.imagePullSecrets" -}}
{{- if .Values.global.imagePullSecrets }}
imagePullSecrets:
{{- toYaml .Values.global.imagePullSecrets | nindent 0 }}
{{- end }}
{{- end -}}

{{- define "cap.podSecurityContext" -}}
runAsNonRoot: true
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{- define "cap.containerSecurityContext" -}}
privileged: false
allowPrivilegeEscalation: false
capabilities:
  drop: ["ALL"]
seccompProfile:
  type: RuntimeDefault
{{- end -}}
