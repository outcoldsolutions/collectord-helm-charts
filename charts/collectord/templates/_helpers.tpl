{{/*
Expand the name of the chart.
*/}}
{{- define "collectord.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "collectord.fullname" -}}
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
{{- define "collectord.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
The workloads' and host state directory's name: the release name, or
legacyWorkloadName to match a shipped manifest (selectors are immutable).
*/}}
{{- define "collectord.workloadName" -}}
{{- default .Release.Name .Values.legacyWorkloadName -}}
{{- end }}

{{/*
collectord.priorityClassName - the shared class, else the workload's own, else its
built-in one (`helm upgrade --reuse-values` over older values has neither).
Takes a dict: root and workload (daemonset or deployment).
*/}}
{{- define "collectord.priorityClassName" -}}
{{- $builtin := dict "daemonset" "system-node-critical" "deployment" "system-cluster-critical" -}}
{{- $values := .root.Values -}}
{{- include "collectord.priorityClassOwn" .root | default (index $values .workload).priorityClassName | default (index $builtin .workload) -}}
{{- end }}

{{/*
collectord.priorityClassOwn - the class both workloads share: priorityClass.name, else
<release>-critical when value is not its default or create is false; empty otherwise.
*/}}
{{- define "collectord.priorityClassOwn" -}}
{{- $pc := .Values.priorityClass -}}
{{- if $pc.name -}}
{{- $pc.name -}}
{{- else if or (ne ($pc.value | int) 1000000000) (and (hasKey $pc "create") (not $pc.create)) -}}
{{- printf "%s-critical" .Release.Name -}}
{{- end -}}
{{- end }}

{{/*
Labels for the namespaced workloads: collectord.labels, but the legacy app
label follows the workload name.
*/}}
{{- define "collectord.workloadLabels" -}}
{{- if .Values.legacyLabels -}}
app: {{ include "collectord.workloadName" . }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- else -}}
{{- include "collectord.labels" . }}
{{- end }}
{{- end }}

{{/*
Common labels applied to all resources
*/}}
{{- define "collectord.labels" -}}
{{- if .Values.legacyLabels -}}
app: {{ .Release.Name }}
{{- else -}}
helm.sh/chart: {{ include "collectord.chart" . }}
{{ include "collectord.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels for the release (common to all workloads)
*/}}
{{- define "collectord.selectorLabels" -}}
{{- if .Values.legacyLabels -}}
daemon: {{ include "collectord.workloadName" . }}
{{- else -}}
app.kubernetes.io/name: {{ include "collectord.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
{{- end }}

{{/*
DaemonSet selector labels
*/}}
{{- define "collectord.daemonset.selectorLabels" -}}
{{ include "collectord.selectorLabels" . }}
{{- if not .Values.legacyLabels }}
app.kubernetes.io/component: worker
{{- end }}
{{- with .Values.daemonset.selectorLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Deployment selector labels
*/}}
{{- define "collectord.deployment.selectorLabels" -}}
{{ include "collectord.selectorLabels" . }}
{{- if not .Values.legacyLabels }}
app.kubernetes.io/component: addon
{{- end }}
{{- with .Values.deployment.selectorLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
collectord.affinity - a workload's affinity with a NotIn for each excludeNodes label in every
required node affinity term, one term when it has none: the terms are alternatives, so each
must leave those nodes out. An empty term matches no node and stays as it is.
Takes a dict: affinity and exclude.
*/}}
{{- define "collectord.affinity" -}}
{{- $affinity := deepCopy (.affinity | default (dict)) -}}
{{- $exclude := list -}}
{{- range $label, $value := .exclude -}}
{{- if not (kindIs "invalid" $value) -}}
{{- $exclude = append $exclude (dict "key" $label "operator" "NotIn" "values" (list (toString $value))) -}}
{{- end -}}
{{- end -}}
{{- if $exclude -}}
{{- $nodeAffinity := $affinity.nodeAffinity | default (dict) -}}
{{- $required := get $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" | default (dict) -}}
{{- $terms := list (dict "matchExpressions" $exclude) -}}
{{- with $required.nodeSelectorTerms -}}
{{- $terms = list -}}
{{- range . -}}
{{- if and (kindIs "map" .) (or .matchExpressions .matchFields) -}}
{{- $terms = append $terms (set (deepCopy .) "matchExpressions" (concat (.matchExpressions | default (list)) $exclude)) -}}
{{- else -}}
{{- $terms = append $terms . -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- $_ := set $required "nodeSelectorTerms" $terms -}}
{{- $_ = set $nodeAffinity "requiredDuringSchedulingIgnoredDuringExecution" $required -}}
{{- $_ = set $affinity "nodeAffinity" $nodeAffinity -}}
{{- end -}}
{{- with $affinity -}}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end -}}
{{- end }}

{{/*
Generate volume mounts for a workload
*/}}
{{- define "collectord.volumeMounts" -}}
{{- $workloadType := .workloadType -}}
{{- $values := .values -}}
{{- range $mount := (index $values.volumeMounts $workloadType) }}
- name: {{ $mount.name }}
  mountPath: {{ $mount.mountPath }}
  {{- if $mount.subPath }}
  subPath: {{ $mount.subPath }}
  {{- end }}
  readOnly: {{ $mount.readOnly | default true }}
{{- end }}
{{- range $projectedVol := (index $values.projectedVolumes $workloadType) }}
- name: {{ $projectedVol.name }}
  mountPath: {{ $projectedVol.mountPath }}
  readOnly: {{ $projectedVol.readOnly | default true }}
{{- end }}
{{- end }}

{{/*
Generate volumes for a workload
*/}}
{{- define "collectord.volumes" -}}
{{- $workloadType := .workloadType -}}
{{- $values := .values -}}
{{- range $mount := (index $values.volumeMounts $workloadType) }}
- name: {{ $mount.name }}
  {{- if $mount.configMap }}
  configMap:
    name: {{ $mount.configMap.name }}
    {{- if $mount.configMap.items }}
    items:
    {{- range $item := $mount.configMap.items }}
    - key: {{ $item.key }}
      path: {{ $item.path }}
      {{- if $item.mode }}
      mode: {{ $item.mode }}
      {{- end }}
    {{- end }}
    {{- end }}
    {{- if $mount.configMap.defaultMode }}
    defaultMode: {{ $mount.configMap.defaultMode }}
    {{- end }}
  {{- else if $mount.secret }}
  secret:
    secretName: {{ $mount.secret.secretName }}
    {{- if $mount.secret.items }}
    items:
    {{- range $item := $mount.secret.items }}
    - key: {{ $item.key }}
      path: {{ $item.path }}
      {{- if $item.mode }}
      mode: {{ $item.mode }}
      {{- end }}
    {{- end }}
    {{- end }}
    {{- if $mount.secret.defaultMode }}
    defaultMode: {{ $mount.secret.defaultMode }}
    {{- end }}
  {{- end }}
{{- end }}
{{- range $projectedVol := (index $values.projectedVolumes $workloadType) }}
- name: {{ $projectedVol.name }}
  projected:
    sources:
    {{- range $source := $projectedVol.sources }}
    {{- if $source.configMap }}
    - configMap:
        name: {{ $source.configMap.name }}
        {{- if $source.configMap.items }}
        items:
        {{- range $item := $source.configMap.items }}
        - key: {{ $item.key }}
          path: {{ $item.path }}
          {{- if $item.mode }}
          mode: {{ $item.mode }}
          {{- end }}
        {{- end }}
        {{- end }}
        {{- if hasKey $source.configMap "optional" }}
        optional: {{ $source.configMap.optional }}
        {{- end }}
    {{- else if $source.secret }}
    - secret:
        name: {{ $source.secret.name }}
        {{- if $source.secret.items }}
        items:
        {{- range $item := $source.secret.items }}
        - key: {{ $item.key }}
          path: {{ $item.path }}
          {{- if $item.mode }}
          mode: {{ $item.mode }}
          {{- end }}
        {{- end }}
        {{- end }}
        {{- if hasKey $source.secret "optional" }}
        optional: {{ $source.secret.optional }}
        {{- end }}
    {{- else if $source.downwardAPI }}
    - downwardAPI:
        items:
        {{- range $item := $source.downwardAPI.items }}
        - path: {{ $item.path }}
          {{- if $item.fieldRef }}
          fieldRef:
            fieldPath: {{ $item.fieldRef.fieldPath }}
            {{- if $item.fieldRef.apiVersion }}
            apiVersion: {{ $item.fieldRef.apiVersion }}
            {{- end }}
          {{- else if $item.resourceFieldRef }}
          resourceFieldRef:
            containerName: {{ $item.resourceFieldRef.containerName }}
            resource: {{ $item.resourceFieldRef.resource }}
            {{- if $item.resourceFieldRef.divisor }}
            divisor: {{ $item.resourceFieldRef.divisor }}
            {{- end }}
          {{- end }}
          {{- if $item.mode }}
          mode: {{ $item.mode }}
          {{- end }}
        {{- end }}
    {{- else if $source.serviceAccountToken }}
    - serviceAccountToken:
        audience: {{ $source.serviceAccountToken.audience }}
        expirationSeconds: {{ $source.serviceAccountToken.expirationSeconds }}
        path: {{ $source.serviceAccountToken.path }}
    {{- end }}
    {{- end }}
    {{- if $projectedVol.defaultMode }}
    defaultMode: {{ $projectedVol.defaultMode }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
A probe whose httpGet names no port gets httpServerBinding's (else 11888): a second
release on the host network moves off 11888, where the other release would answer.
*/}}
{{- define "collectord.probe" -}}
{{- $probe := deepCopy .probe -}}
{{- if and (kindIs "map" $probe.httpGet) (empty $probe.httpGet.port) -}}
{{- $port := last (splitList ":" (.binding | default "")) -}}
{{- if not (regexMatch "^[0-9]+$" $port) -}}
{{- $port = "11888" -}}
{{- end -}}
{{- $_ := set $probe.httpGet "port" (atoi $port) -}}
{{- end -}}
{{- toYaml $probe -}}
{{- end }}

{{/*
The Splunk metrics-index keys of one input; the caller guards on indexType, metricsIndex
and metricsOutput, which only the Splunk charts' values carry. indexType renders only when
set, so the input takes [general] defaultIndexType. suffixes: the per-stream keys (host,
cgroup) or none.
*/}}
{{- define "collectord.metricsRouting" -}}
{{- $v := .values -}}
# indexType (events, metrics or both) overrides [general] defaultIndexType. Set metricsIndex or
# [output.splunk] defaultMetricsIndex: the HEC token's default index is normally an events index.
# metricsOutput: an output whose HEC token can write to the metrics index.
{{- if hasKey $v "indexType" }}
indexType = {{ $v.indexType }}
{{- end }}
{{- if .suffixes }}
{{- range $s := .suffixes }}
metricsIndex.{{ $s }} = {{ index ($v.metricsIndex | default dict) $s | default "" }}
{{- end }}
{{- range $s := .suffixes }}
metricsOutput.{{ $s }} = {{ index ($v.metricsOutput | default dict) $s | default "" }}
{{- end }}
{{- else }}
metricsIndex = {{ $v.metricsIndex | default "" }}
metricsOutput = {{ $v.metricsOutput | default "" }}
{{- end }}
{{- end }}

{{/*
collectord.environment - "openshift" or "kubernetes", the prefix of the fields Collectord
composes for workloads (openshift_namespace on OpenShift, never kubernetes_namespace), which
every field name and index name in an example must use. Takes the root context.
*/}}
{{- define "collectord.environment" -}}
{{- .Values.environment | default (ternary "openshift" "kubernetes" (contains "collectorforopenshift" .Values.image.repository)) -}}
{{- end -}}

{{/*
collectord.namespaceField - the field an event's namespace is sent under, which the
namespace filter examples must name (any other key matches nothing).
Takes a dict: root and output (empty: defaultOutput).
*/}}
{{- define "collectord.namespaceField" -}}
{{- $values := .root.Values -}}
{{- $general := $values.configuration.general -}}
{{- $environment := include "collectord.environment" .root -}}
{{- $separator := $general.fieldsSeparator | default (ternary "." "_" (not (empty $values.configuration.outputs.elasticsearch))) -}}
{{- $field := printf "%s%snamespace" $environment $separator -}}
{{- $output := .output | default $general.defaultOutput | default "" -}}
{{- if and (hasPrefix "elasticsearch" $output) (eq $field "kubernetes.namespace") -}}
kubernetes.namespace.name
{{- else -}}
{{ $field }}
{{- end -}}
{{- end -}}

{{/*
collectord.configChecksum - a digest of the ConfigMap keys one workload mounts, so
another workload's file does not roll it; empty with configMap.create false.
Takes a dict: root, keys and extra (the additional-files maps it mounts).
*/}}
{{- define "collectord.configChecksum" -}}
{{- if .root.Values.configMap.create -}}
{{- $rendered := include (print .root.Template.BasePath "/configmap.yaml") .root | fromYaml -}}
{{- $data := dict -}}
{{- if and $rendered (hasKey $rendered "data") }}{{ $data = $rendered.data }}{{ end -}}
{{- $keys := list -}}
{{- range .keys }}{{ $keys = append $keys . }}{{ end -}}
{{- range .extra }}{{ range $k, $_ := . }}{{ $keys = append $keys $k }}{{ end }}{{ end -}}
{{- $picked := dict -}}
{{- range $keys }}{{ if hasKey $data . }}{{ $_ := set $picked . (index $data .) }}{{ end }}{{ end -}}
{{- toYaml $picked | sha256sum -}}
{{- end -}}
{{- end -}}

{{/*
collectord.tidyConf - a conf file's text, indented for the ConfigMap, with its blank lines settled
whatever the values switch on or off: none before the first line or after the last, never two in
a row, and one where a setting is followed by a [section] or by the next setting's comment.
*/}}
{{- define "collectord.tidyConf" -}}
{{- $s := regexReplaceAll `(?m)^[ \t]+$` . "" -}}
{{- $s = regexReplaceAll `\n{3,}` $s "\n\n" -}}
{{- $s = regexReplaceAll `(?m)^(    [^#;/\s\[][^\n]*)\n(    [\[#;])` $s "${1}\n\n${2}" -}}
{{- trimAll "\n" $s -}}
{{- end -}}

{{/*
collectord.repeat - the repeat* keys of a log input: the ones the values carry set, the
others commented with their defaults. Takes a dict: values, root, unit (stream, file or
writer), annotation (optional), note (optional) and budget (optional).
*/}}
{{- define "collectord.repeat" -}}
{{- $v := .values -}}
# Group each {{ .unit }}'s repeated lines into one event per run that counts them.
# Off unless true{{ with .annotation }}; a workload overrides it with its
# {{ with $.root.Values.configuration.general.annotationsSubdomain }}{{ . }}.{{ end }}collectord.io/{{ . }} annotation{{ end }}.
{{- with .note }}
# {{ . }}
{{- end }}
repeatEnabled = {{ $v.repeatEnabled }}

# How long a run is held before its event goes out, up to 10m (a crash resends up to that much)
{{ if hasKey $v "repeatMaxSpan" }}repeatMaxSpan = {{ $v.repeatMaxSpan }}{{ else }}# repeatMaxSpan = 1m{{ end }}

# Add every line's time to a run's event (collectord_repeat_offsets, milliseconds from its own)
{{ if hasKey $v "repeatOffsets" }}repeatOffsets = {{ $v.repeatOffsets }}{{ else }}# repeatOffsets = false{{ end }}

# What {{ .budget | default (printf "each %s" .unit) }} may remember: distinct lines, lines one event stands for, and bytes
{{ if hasKey $v "repeatMaxKeys" }}repeatMaxKeys = {{ $v.repeatMaxKeys }}{{ else }}# repeatMaxKeys = 256{{ end }}
{{ if hasKey $v "repeatMaxCount" }}repeatMaxCount = {{ $v.repeatMaxCount }}{{ else }}# repeatMaxCount = 1000{{ end }}
{{ if hasKey $v "repeatMaxBytes" }}repeatMaxBytes = {{ $v.repeatMaxBytes }}{{ else }}# repeatMaxBytes = 256KB{{ end }}
{{- end }}

{{/*
collectord.fold - the fold* keys of a log input, as collectord.repeat writes its own.
*/}}
{{- define "collectord.fold" -}}
{{- $v := .values -}}
# Fold each {{ .unit }}'s lines of one pattern past foldMaxPerMinute into one summary a minute.
# Lossy: folded lines are not sent. Off unless true{{ with .annotation }}; a workload overrides it with its
# {{ with $.root.Values.configuration.general.annotationsSubdomain }}{{ . }}.{{ end }}collectord.io/{{ . }} annotation{{ end }}.
{{- with .note }}
# {{ . }}
{{- end }}
foldEnabled = {{ $v.foldEnabled }}

# Lines of one pattern a minute sent before the rest fold
{{ if hasKey $v "foldMaxPerMinute" }}foldMaxPerMinute = {{ $v.foldMaxPerMinute }}{{ else }}# foldMaxPerMinute = 60{{ end }}

# Lines never folded (a regular expression; empty: the default)
{{ if hasKey $v "foldKeep" }}foldKeep = {{ $v.foldKeep }}{{ else }}# foldKeep = (?i)error|exception|fatal|panic{{ end }}

# What {{ .budget | default (printf "each %s" .unit) }} may keep a minute: its patterns and summaries
{{ if hasKey $v "foldMaxBytes" }}foldMaxBytes = {{ $v.foldMaxBytes }}{{ else }}# foldMaxBytes = 256KB{{ end }}
{{- end }}

{{/*
collectord.patterns - the patterns* keys of a log input, as collectord.repeat writes its
own, plus scope (whose top patterns a report carries).
*/}}
{{- define "collectord.patterns" -}}
{{- $v := .values -}}
# Report {{ .scope | default (printf "each %s's" .unit) }} top patterns every interval, as events of their own.
# Off unless true{{ with .annotation }}; a workload overrides it with its
# {{ with $.root.Values.configuration.general.annotationsSubdomain }}{{ . }}.{{ end }}collectord.io/{{ . }} annotation{{ end }}.
{{- with .note }}
# {{ . }}
{{- end }}
patternsEnabled = {{ $v.patternsEnabled }}

# How often a report goes out, from 1m to 24h
{{ if hasKey $v "patternsInterval" }}patternsInterval = {{ $v.patternsInterval }}{{ else }}# patternsInterval = 15m{{ end }}

# How many patterns a report carries, up to 100
{{ if hasKey $v "patternsTop" }}patternsTop = {{ $v.patternsTop }}{{ else }}# patternsTop = 20{{ end }}

# What {{ .scope | default (printf "each %s's" .unit) }} patterns may keep; past it a new one takes the place of the lightest
{{ if hasKey $v "patternsMaxBytes" }}patternsMaxBytes = {{ $v.patternsMaxBytes }}{{ else }}# patternsMaxBytes = 256KB{{ end }}

# The report events' type (empty: the input's type with _patterns after it)
{{ if hasKey $v "patternsType" }}patternsType = {{ $v.patternsType }}{{ else }}# patternsType ={{ end }}
{{- end }}

{{/*
The container image: repository:tag, and @digest when image.digest pins it.
*/}}
{{- define "collectord.image" -}}
{{- $image := .Values.image -}}
{{- with $image.digest -}}
{{- if not (regexMatch "^sha256:[0-9a-f]{64}$" .) -}}
{{- fail (printf "image.digest %q: give sha256: and the 64 lowercase hex digits of the image's digest" .) -}}
{{- end -}}
{{- end -}}
{{- printf "%s:%s" $image.repository (toString $image.tag) -}}
{{- with $image.digest }}@{{ . }}{{ end -}}
{{- end -}}
