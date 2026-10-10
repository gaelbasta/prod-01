{{/* Étiquettes communes à tous les objets du projet */}}
{{- define "plateforme.labels" -}}
{{ include "plateforme.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | toString | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
plateforme.gba-lab.win/profil: {{ .Values.profile }}
{{- end }}

{{/* Étiquettes qui relient le Deployment, ses pods et le Service (ne jamais les changer) */}}
{{- define "plateforme.selectorLabels" -}}
app.kubernetes.io/name: {{ .Release.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* Port du conteneur : valeur « port », sinon défaut du profil */}}
{{- define "plateforme.port" -}}
{{- if .Values.port -}}{{ .Values.port }}{{- else if eq .Values.profile "static" -}}8080{{- else -}}8000{{- end -}}
{{- end }}

{{/* Route de santé : valeur « healthPath », sinon défaut du profil */}}
{{- define "plateforme.healthPath" -}}
{{- if .Values.healthPath -}}{{ .Values.healthPath }}{{- else if eq .Values.profile "static" -}}/{{- else -}}/healthz{{- end -}}
{{- end }}

{{/* Contrôles avec messages en français : bloquent le déploiement si une valeur est manquante ou dangereuse */}}
{{- define "plateforme.validate" -}}
{{- if not .Values.image.repository -}}
{{- fail "\n\n[plateforme] image.repository est obligatoire (ex. ghcr.io/gaelbasta/prism)\n" -}}
{{- end -}}
{{- if not .Values.image.tag -}}
{{- fail "\n\n[plateforme] image.tag est obligatoire : une version figée (ex. 1.0.0)\n" -}}
{{- end -}}
{{- if eq (toString .Values.image.tag) "latest" -}}
{{- fail "\n\n[plateforme] image.tag ne doit jamais valoir « latest » (PLATFORM_STANDARD)\n" -}}
{{- end -}}
{{- if not .Values.host -}}
{{- fail "\n\n[plateforme] host est obligatoire (ex. prism.prod.gba-lab.win)\n" -}}
{{- end -}}
{{- if and .Values.persistence.enabled (eq .Values.profile "static") -}}
{{- fail "\n\n[plateforme] persistence est réservé au profil app : en static, les fichiers sont dans l'image\n" -}}
{{- end -}}
{{- if and .Values.persistence.enabled (gt (int .Values.replicas) 1) -}}
{{- fail "\n\n[plateforme] avec persistence, replicas doit valoir 1 (volume local à écriture unique)\n" -}}
{{- end -}}
{{- end }}
