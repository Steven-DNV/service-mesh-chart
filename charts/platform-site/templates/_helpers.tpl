{{/*
Expand the name of the chart.
*/}}
{{- define "platform-site.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "platform-site.fullname" -}}
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
{{- define "platform-site.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "platform-site.labels" -}}
helm.sh/chart: {{ include "platform-site.chart" . }}
{{ include "platform-site.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "platform-site.selectorLabels" -}}
app.kubernetes.io/name: {{ include "platform-site.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "platform-site.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "platform-site.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}


{{- define "platform-site.commonOptions" -}}

{{- $timeout := include "platform-site.getValueFromSources" (dict "valueName" ".timeout" | mustMergeOverwrite .) }}
{{- if $timeout }}
    timeout: {{ $timeout }}
{{- end }}

{{- if (include "platform-site.getBoolFromSources" (dict "valueName" ".retries.enabled" | mustMergeOverwrite .) | eq "true") }}
    retries:
{{ include "platform-site.getValueFromSources" (dict "valueName" ".retries.settings" | mustMergeOverwrite .) | required "retry settings are required" | trim | indent 6 }}
{{- else }}
    # retries: disabled (enabled: {{ include "platform-site.getValueFromSources" (dict "valueName" ".retries.enabled" | mustMergeOverwrite .) }})
{{- end }}
{{- end -}}


{{- define "platform-site.serviceName" -}}
{{ .serviceName | replace "." "-" }}
{{- end -}}

{{- define "platform-site.isComponentEnabledInSource" }}
{{- /*
  Given a .source and a .componentName, return whether that component is .enabled
  Currently used from the valuePrecedence template to check multiple sources
  return "true", "false", or "" if no value set
*/ -}}
{{- $componentName := "{{ .componentName }}"}}
{{- $enabled := printf "{{- if .source.%s }}{{- .source.%s.enabled }}{{- end}}" .componentName .componentName }}
{{- tpl $enabled . }}
{{- end }}


{{- define "platform-site.getSourceValue" }}
{{- /*
  Given a .source and a .valueName, return the value
  Return "" if any part of the path is undefined
  Currently used from the valuePrecedence template to check multiple sources
*/ -}}
{{- $valueNameList := .valueName | splitList "." }}
{{- /* Use mutable value in the dictionary to track component - todo, use separate dict this and acm as well */ -}}
{{- $_ := set . "missingComponent" false }}
{{- range $i, $iName := $valueNameList }}
  {{- /* Variables do not carry state across iterations, so reconstruct the name up to this point */ -}}
  {{- $acmValueName := slice $valueNameList 0 (add $i 1) | join "." }}
  {{- if and (not $.missingComponent) (ne $acmValueName ".") }}
    {{- $hasValue := (tpl (printf "{{- .source%s -}}" $acmValueName) $) }}
    {{- if not $hasValue }}
        {{- $_ := set $ "missingComponent" true }}
    {{- else if eq $acmValueName $.valueName }}
      {{- /* We've got the whole value name verified, return the value toYaml (for when the value refers to a map)*/}}
      {{- $lookupTemplate := printf "{{- .source%s | toYaml -}}" $acmValueName }}
      {{- $curValue := (tpl $lookupTemplate $) }}
      {{- $curValue }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}


{{- define "platform-site.getValueFromSources" }}
{{- /*
  Given a .valueName and version, service, and default sources
  return the component value given the precedence of version, service, and then default sources
*/ -}}
{{- $versionSource := required "versionSource is required" .versionSource }}
{{- $serviceSource := required "serviceSource is required" .serviceSource }}
{{- $defaultSource := required "defaultSource is required" .defaultSource }}
{{- $args := dict "valueName" (required "valueName is required" .valueName) "source" $versionSource "Template" (required "Template parameter is required - use $.Template" $.Template) }}
{{- $versionValue := include "platform-site.getSourceValue" $args }}
{{- if ne $versionValue "" }}
  {{- $versionValue }} # (version-specific)
{{- else }}
  {{- $serviceValue := include "platform-site.getSourceValue" (set $args "source" $serviceSource) }}
  {{- if ne $serviceValue "" }}
    {{- $serviceValue }} # (service level)
  {{- else }}
    {{- $defaultValue := include "platform-site.getSourceValue" (set $args "source" $defaultSource) }}
    {{- $defaultValue }} # (default)
  {{- end }}
{{- end }}
{{- end }}

{{- define "platform-site.getBoolFromSources" }}
{{- /*
  Given a .valueName and version, service, and default sources, return a boolean
  return the component value given the precedence of version, service, and then default sources
  Value is expected to be defined at a minimum in default
  only true/false values are returned
*/ -}}
{{- $strValue := include "platform-site.getValueFromSources" . }}
{{- $strValue | substr 0 4 | eq "true" -}}{{- /* $strValue }} / {{ $strValue | substr 0 4 }} / {{ $strValue | substr 0 4 | eq "true" */}}
{{- end }}


{{- define "platform-site.isComponentEnabled" }}
{{- /*
  Given a .componentName and version, service, and default sources
  return whether that component is .enabled by going through the version, service, and then default sources
  returns true or false
*/ -}}
{{- $version := include "platform-site.isComponentEnabledInSource" (dict "source" .versionSource "componentName" .componentName "Template" $.Template) }}
{{- if ne $version "" }}
  {{- $version | eq "true" -}}
{{- else }}
  {{- $service := include "platform-site.isComponentEnabledInSource" (dict "source" .serviceSource "componentName" .componentName "Template" $.Template) }}
  {{- if ne $service "" }}
    {{- $service | eq "true" -}}
  {{- else }}
    {{- $default := include "platform-site.isComponentEnabledInSource" (dict "source" .defaultSource "componentName" .componentName "Template" $.Template) }}
    {{- $default | eq "true" -}}
  {{- end }}
{{- end }}
{{- end }}


{{- define "platform-site.externalMatcher" }}

{{- $sanitizedServiceName := .serviceName | replace "." "-" }}
{{- $sanitizedVersion := .versionSource.version | replace "." "-" }}
{{- /* args for templates which look across sources */}}
{{- $routeName := printf "%s-%s-route" $sanitizedServiceName $sanitizedVersion }}

  # Routing for {{ printf "%s / version: %s" $sanitizedServiceName $sanitizedVersion }}
{{- $prefixes := default .serviceSource.urlPrefixes .versionSource.urlPrefixes }}
{{- /* $prefixes := include "platform-site.getValueFromSources" (dict "valueName" ".urlPrefixes" | mustMergeOverwrite .sourcesArgs) | toYaml */}}

{{- /* mutually exclusive settings, exactPrefixMatch takes precedence */}}
{{- $exactPrefixMatch := include "platform-site.getBoolFromSources" (dict "valueName" ".exactPrefixMatch" | mustMergeOverwrite .sourcesArgs) | eq "true" }}
{{- $redirectOnTrailingSlash := and (not $exactPrefixMatch) (include "platform-site.getBoolFromSources" (dict "valueName" ".redirectOnNoTrailingSlash" | mustMergeOverwrite .sourcesArgs) | eq "true" ) }}

{{- if $prefixes }}
{{- if $redirectOnTrailingSlash }}
{{- range $prefixes }}
{{- $slashPrefix := printf "/%s" . }}
  - name: {{ printf "%s-%s-redirect" $sanitizedServiceName $sanitizedVersion }}
    match:
      - uri:
          exact: {{ $slashPrefix }}
    redirect:
      uri: {{ $slashPrefix }}/
{{- end }} {{/* end range prefixes */}}
{{- end }} {{/* end redirect on no trailing slash */}}
  - name: {{ $routeName }}
    match:
{{- range $prefixes }}
{{- if hasPrefix "/" . }}
  {{ fail "url prefixes must not include leading slash"}}
{{- end }}
{{- $slashPrefix := printf "/%s" . }}
{{- if $exactPrefixMatch }}
    - uri:
        exact: {{ $slashPrefix }}
{{- end }}        
    - uri:
        prefix: {{ $slashPrefix }}/
{{- end }} {{- /* end range prefixes */}}
{{- end }} {{- /* end if prefixes */}}

{{- $istioMatch := default .serviceSource.externalIstioMatch .versionSource.externalIstioMatch }}
{{- if $istioMatch }}
  - name: {{ $routeName }}
    match:
    #custom match
{{ $istioMatch | toYaml | indent 4 }}
{{- end }}  {{- /* end if externalIstioMatch */}}

{{- if not (or $prefixes $istioMatch) }}

  - name: catch-all-{{ $routeName }}
{{- end }}  {{- /* no prefix or istio match specification */}}

{{- end }} {{- /* end define */}}
