# Collectord Helm Charts for Monitoring OpenShift in Splunk Enterprise and Splunk Cloud

This helm chart provides a way to deploy Collectord in OpenShift clusters for monitoring OpenShift in Splunk Enterprise and Splunk Cloud.
Please refer to the documentation on how to install Monitoring OpenShift application in Splunk [here](https://www.outcoldsolutions.com/docs/monitoring-openshift/).

## Prerequisites

- OpenShift 4.11+
- Helm 3.8+

## Pod security

The DaemonSet reads the node's filesystem, journal and cgroup tree through a host mount, runs
on the host network and is privileged; the chart ships the SecurityContextConstraints that admits
it, bound to the release's service account, and OpenShift's Pod Security Admission label sync
follows that grant. The addon Deployment (the cluster-wide watcher for events, objects and
annotated Prometheus endpoints) runs without privileges, capabilities or privilege escalation and
under the runtime's default seccomp profile (`collectord.deployment.securityContext`). It runs as
root, and in the `spc_t` SELinux domain, only to read the state directory it shares with the
DaemonSet on its node: a hostPath the DaemonSet writes as root, which is never relabeled, so a
confined container could not read it.

The ClusterRole grants read access to the objects Collectord attaches as metadata and
`nodes/metrics` for the kubelet scrape, which goes to the kubelet on the node directly, at the
node's own IP (`https://${KUBERNETES_NODEIP}:10250/metrics`, read from the downward API). Not
loopback: the kubelet always listens on the node IP and holds that port before any pod can, while
loopback is free for a host-network pod to take and be handed the bearer token, the serving
certificate not being verified (OpenShift signs it with its kubelet-serving CA, not the service
account CA; point `certPath` at that CA and set `insecure: false` to verify, which also closes the
one residual exposure of an unverified scrape: a host-network pod that takes the port while the
kubelet restarts is handed the collector's read-only token). It does not grant `nodes/proxy`: that
subresource is only needed to reach the kubelet through the API server's node proxy, and a `get`
on it is enough to exec into any pod on the node - the same token, exec everywhere, with nothing
to race.

On `secrets` it grants `get` and nothing else - never `list` or `watch`, which cluster-wide
return the contents of every Secret in the cluster. The one feature that reads a Secret is a
`SplunkOutput` custom resource whose `spec.tokenFromSecret` names a Secret and a key instead of
carrying the HEC token inline: when an `output` setting points at that resource
(`splunk::user/<namespace>/<name>`, set through a `collectord.io/output` annotation or the
configuration), Collectord reads that one Secret by name, in that namespace. An annotation on a pod
or a namespace, or one a `Configuration` resource gives a pod, may name only a `SplunkOutput` of the
object's own namespace: naming another namespace's would send its data with that namespace's token
into that namespace's indexes, so Collectord rejects the annotation and keeps the output it would
have replaced. Set `configuration.general.kubernetes.crossNamespaceUserOutputs: true` where one
`SplunkOutput` serves several namespaces on purpose. If you add an
`[input.kubernetes_watch::...]` section with `kind = Secret`, that watch needs `list` and `watch`
on Secrets; add them under `collectord.clusterRole.rules` yourself, and prefer a namespace-scoped
watch and Role where you can.

The DaemonSet runs under the built-in `system-node-critical` PriorityClass and the addon Deployment
under `system-cluster-critical`, as a node's own agents do. The kubelet never evicts pods of these
classes, and while a node is under disk pressure it admits no other: under any lower class
Collectord is evicted and its replacement refused until the pressure ends, so the node stops
reporting when its disk alerts matter most. A new addon pod (an upgrade, a deleted pod) still waits
for a node without disk pressure: the scheduler places a pod on one only if it tolerates the
`node.kubernetes.io/disk-pressure` taint, as the DaemonSet's do. The scheduler and the kubelet
preempt lower-priority pods to make room for a Collectord pod that does not fit, and no eviction
bounds Collectord's own disk use, so Collectord bounds it: it lets go of the rotated logs it holds
open once the log filesystem's free space falls under
`[input.files] retainedLogsMinFreeSpacePercent` (20 by default). Kubernetes admits these classes in
any namespace, but a cluster can limit them to namespaces holding a ResourceQuota scoped to them, as
GKE Standard does; the chart renders one in the release namespace
(`collectord.priorityClass.resourceQuota`), which limits nothing elsewhere. To run both workloads
under a class of their own instead, as releases before 26.10.1 did, set
`collectord.priorityClass.name: collectorforopenshift-critical`: the chart creates it at the highest
value a user-defined class may have (`collectord.priorityClass.value`). With
`collectord.priorityClass.create: false` the name is a class that exists already
(`collectorforopenshift-critical` when none is set), and `collectord.daemonset.priorityClassName`
and `collectord.deployment.priorityClassName` name each workload's class apart.

Critical pods are also stopped last on a graceful node shutdown, in the kubelet's
`shutdownGracePeriodCriticalPods` window, which is where a log shipper wants to be, after the pods
whose last lines it forwards. Collectord's own shutdown drain, `[general] shutdownTimeout`, has to
fit inside that window and inside the pod's own grace period: the chart leaves
`terminationGracePeriodSeconds` at the Kubernetes default of 30 seconds, and a longer drain needs
it raised (`collectord.daemonset.terminationGracePeriodSeconds`, and the `deployment` twin), or the
kubelet kills the pod mid-drain.

## Getting Started

At this point we assume that you have installed Monitoring OpenShift application in Splunk, and enabled Splunk HTTP Event Collector (HEC). Please refer to
[Monitoring OpenShift - Installation](https://www.outcoldsolutions.com/docs/monitoring-openshift/installation/) on how to do that.

Review and accept [license agreement](https://www.outcoldsolutions.com/legal/license-agreement/). If your organization has not purchased a license, 
request an evaluation license key with [this automated form](https://www.outcoldsolutions.com/trial/request/). License key will be sent to your email address immediately on request.

Create a file named `my_values.yaml` with the content similar to:

```yaml
collectord:
  configuration:
    general: 
      acceptLicense: true
      license: '<your_license_key>'
      fields:
        openshift_cluster: 'dev'
    outputs:
      splunk:
        default:
          url: 'https://hec.example.com:8088/services/collector/event/1.0'
          token: 'B5A79AAD-D822-46CC-80D1-819F80D7BFB0'
          insecure: true
```

Where you will agree to the license agreement, include your license key, and configure Splunk default output. 

You can generate a YAML file for deployment using the following command:

```bash
helm template collectorforopenshift \
    --namespace collectorforopenshift \
    --create-namespace \
    --include-crds \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-splunk-openshift > collectorforopenshift.yaml
```

To install the chart, run the following command:

```bash
helm install collectorforopenshift \
    --namespace collectorforopenshift \
    --create-namespace \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-splunk-openshift
```

The chart and Collectord's image come from `registry.outcold.solutions`, whose pulls also reach
`ghcr.io` and `pkg-containers.githubusercontent.com`: where egress is filtered, allow all three.
Docker Hub has the same chart, `oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift`,
and the same images: to pull the image from there, set
`collectord.image.repository: docker.io/outcoldsolutions/collectorforopenshift`.

To pin the image by digest, set `collectord.image.digest` to the `sha256:` digest of the tag you pull;
the tag then only labels it. Look the digest up with
`docker buildx imagetools inspect registry.outcold.solutions/outcoldsolutions/collectorforopenshift:<tag>`
(the `Digest:` line). The FIPS tag and the Red Hat certified image have digests of their own.

## Configuration

Collectord is configured using the `ini` file format. You can find a reference with all possible configurations [here](https://www.outcoldsolutions.com/docs/monitoring-openshift/reference/).
This helm chart allows you to customize and override those configurations.
Using `my_values.yaml` as a template, you can customize the configuration to suit your needs. Please refer to the [./values.yaml](./values.yaml) for default configuration and possible values.

### Using secrets

If you want to store some configurations in a secret, first you need to create a secret with the `ini` format, that Collectord can read from. For example, if we want to store license, and token in secret file,
first we will create a secret file with the `ini` format and `.conf` extension with name `101-general.conf`.

```ini
[general]
license = <your_license_key>

[output.splunk]
token = B5A79AAD-D822-46CC-80D1-819F80D7BFB0
```

Using this file we can create a secret using the `ini` file:

```bash
oc new-project collectorforopenshift
oc create secret generic collectord-secret \
  --from-file=101-general.conf=101-general.conf \
  -n collectorforopenshift
```

After that we can remove values that we provided in the secret file in the `my_values.yaml` file.

```yaml
collectord:
  secrets:
    - name: collectord-secret

  configuration:
    general: 
      acceptLicense: true
      fields:
        openshift_cluster: 'dev'
    outputs:
      splunk:
        default:
          url: 'https://hec.example.com:8088/services/collector/event/1.0'
          insecure: true
```

And install it using the following command (don't need to create namespace as we already created it):

```bash
helm install collectorforopenshift \
    --namespace collectorforopenshift \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-splunk-openshift
```

> NOTE: Collectord reads all files with `.conf` extension from the `/config` directory and subdirectories. It will sort them by name in ascending order before reading them.
> In a case of file names `001-general.conf` and `101-general.conf`, all values in `101-general.conf` will override values in `001-general.conf`.

### Secondary Splunk Output

Collectord supports multiple Splunk outputs. You can configure an additional Splunk output by adding a new section to the `my_values.yaml` file. For example:

```yaml
collectord:
  configuration:
    general: 
      acceptLicense: true
      fields:
        openshift_cluster: 'dev'
    outputs:
      splunk:
        default:
          url: 'https://hec.example.com:8088/services/collector/event/1.0'
          token: 'B5A79AAD-D822-46CC-80D1-819F80D7BFB0'
          insecure: true
        apps:
          url: 'https://hec-apps.example.com:8088/services/collector/event/1.0'
          token: '107E857B-C311-4C72-97E4-FBE601A6B39E'
          insecure: true
```

After that you can reference this output in annotations like `collectord.io/output=splunk::apps`

### Sending metrics to a Splunk metrics index

Every metrics-producing input ships shaped for an events index, which is what the Monitoring
OpenShift app has always read: `general.defaultIndexType` is `events`. Set it to `metrics` to
send Splunk metrics-index records instead, or to `both` to send the two at once, so you can
compare the events dashboards against their metrics-index twins before you switch. It covers
every input that sets no `indexType` of its own: the stats inputs, Collectord's own metrics,
Prometheus auto-discovery, every `prometheus` scrape and every script of `format: prometheus`.
Name the index once on the output:

```yaml
collectord:
  configuration:
    general:
      defaultIndexType: both
    outputs:
      splunk:
        default:
          url: 'https://hec.example.com:8088/services/collector/event/1.0'
          token: 'B5A79AAD-D822-46CC-80D1-819F80D7BFB0'
          defaultMetricsIndex: 'openshift_metrics'
```

An input's own `indexType` wins over the default (`inputs.procStats.indexType: events` keeps the
process stats on the events index), and a pod's `collectord.io/prometheus.<n>-indexType`
annotation wins for that endpoint.

The index must be a metrics index in Splunk and the HEC token must be allowed to write it: a
metrics-index record sent to an events index is indexed as the literal text `metric` and no
`mstats` search will find it. An input can name its own index with `metricsIndex`, and carry it
through a different output with `metricsOutput` (a `splunk::<name>` output whose own token can
write that index). `systemStats` and `netStats` sample a host stream and a cgroup stream, and
take `metricsIndex.host` / `metricsIndex.cgroup` (and the matching `metricsOutput.*`) when the
two should not go to the same place.

A workload whose `collectord.io/output` annotation names an output of its own (an
`[output.splunk::<name>]`, or a `SplunkOutput` object as `splunk::user/<namespace>/<name>`) keeps
its metrics-index records on that output, in that output's `defaultMetricsIndex`, whatever the
inputs name. Give a team's output the team's metrics index, so its token never needs the shared
one. A `SplunkOutput` takes the rest of its settings from the default output, and sets these
in its own `spec`:

```yaml
apiVersion: collectord.io/v1
kind: SplunkOutput
metadata:
  name: team
  namespace: team-a
spec:
  token: '<the team token>'
  defaultMetricsIndex: team_a_metrics
  incorrectIndexBehavior: Drop
  requireExplicitIndex: false
```

Helm installs the `SplunkOutput` definition (`crds/`) only on the first install. To use these
fields on a cluster installed with an earlier chart, apply the current definition first:
`helm show crds <chart> | oc apply -f -`. Without it `oc apply` refuses the new fields,
and a tool that skips validation has them dropped.

### Measuring every filesystem of a node

By default Collectord measures one filesystem per node, the one holding the kubelet's root
directory (`mounts: root`). `mounts: auto` measures every real filesystem of the node's mount
table instead - a data disk, an NFS share, a FUSE mount beside the root - one record per mount,
read again on every interval so a volume mounted later is measured without a restart. The record
of the filesystem holding the kubelet's root directory carries `openshift_mount_runtime = true`: the
Monitoring OpenShift app's Runtime storage table and its runtime disk alerts read that one, its
Filesystems table lists them all, and its Alert Catalog's *Node filesystem below N percent free*
templates watch the others (Monitoring OpenShift 26.10.1 or later; an older app reads any of them as
the runtime's).

```yaml
collectord:
  configuration:
    inputs:
      mountStats:
        mounts: auto
        # optional: the filesystem types to measure, and the mount points to leave out
        include: '^(ext4|xfs|nfs4?)$'
        exclude: '^/(proc|sys|dev|run|boot)(/|$)|^/var/lib/(docker|containers|kubelet)/'
```

`include` is a regular expression the filesystem type has to match, and `exclude` one the mount
point must not match; left empty, they keep Collectord's defaults, which the rendered
`[input.mount_stats]` section describes.

### Secondary Collectord deployment

Collectord has ability to forward logs to multiple Splunk outputs simultaneously. In the example above, you can use annotations like `collectord.io/output=splunk,splunk::apps` 
to forward logs to both outputs. But there are limitations about if you want to apply some transofrmation logic using the annotations, as this logic will be applied to both outputs at the same time.

Say we will have two Collectord deployments, one forwarding data to Splunk Enterprise and another to Splunk Cloud. First we will deploy configuration for Splunk Enterprise `splunkenterprise_values.yaml`. 
For example:

```yaml
collectord:
  configuration:
    general: 
      acceptLicense: true
      license: '<your_license_key>'
      fields:
        openshift_cluster: 'dev'
    outputs:
      splunk:
        default:
          url: 'https://hec.example.com:8088/services/collector/event/1.0'
          token: 'B5A79AAD-D822-46CC-80D1-819F80D7BFB0'
          insecure: true
```

And we will deploy it with 

```bash
helm install collectorforopenshift \
    --namespace collectorforopenshift \
    --create-namespace \
    -f splunkenterprise_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-splunk-openshift
```

Secondary we will create a configuration file for Splunk Cloud `splunkcloud_values.yaml`, where we will call this deployment
`collectorforopenshift-cloud`, and reference already created objects like service account and cluster role,
created with previous deployment.
For example:

```yaml
collectord:
  serviceAccount:
    create: false
    name: collectorforopenshift
  
  clusterRole:
    create: false
    name: collectorforopenshift
  
  configuration:
    general: 
      annotationsSubdomain: 'splunkcloud'
      # The first release's DaemonSet already holds 11888 on every node's host network.
      httpServerBinding: '127.0.0.1:11889'
      acceptLicense: true
      license: '<your_license_key>'
      fields:
        openshift_cluster: 'dev'
    outputs:
      splunk:
        default:
          url: 'https://hec-apps.example.com:8088/services/collector/event/1.0'
          token: '107E857B-C311-4C72-97E4-FBE601A6B39E'
          insecure: true
```

The second release moves its internal http server to `11889`. Both releases' DaemonSets run on the
host network of the same nodes, and two servers cannot bind one port: left on `11888`, the second
one logs `failed to start http server … address already in use` at every start, and its probes
are answered by the first release's server, so it would look healthy even when it is not. The
liveness and readiness probes and the addon follow `httpServerBinding`'s port, so this one value
moves them all.

To deploy it, you will run command, where we reference the same namespace (and ClusterRole, ClusterRoleBinding, ServiceAccount), but create separate DaemonSet, StatefulSets and Deployments specifically for the Splunk Cloud deployment.

```bash
helm install collectorforopenshift-cloud \
    --namespace collectorforopenshift \
    -f splunkcloud_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-splunk-openshift
```

### Collecting Collectord's own metrics

Collectord serves its internal metrics in Prometheus format on `/metrics/prometheus`, from the same
internal http server that serves the health probes. This chart already runs that server for the
probes, on `127.0.0.1:11888`, with only the `/healthz` and `/readyz` endpoints enabled. To let
Prometheus collect the metrics, enable that endpoint too, widen the bind address so the scraper can
reach it, declare the port on each workload, and annotate the pods:

```yaml
collectord:
  configuration:
    general:
      httpServerBinding: "0.0.0.0:11888"
      "httpServerEndpoints.metrics": true

  daemonset:
    ports:
      - name: metrics
        containerPort: 11888
        protocol: TCP
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "11888"
      prometheus.io/path: "/metrics/prometheus"

  deployment:
    ports:
      - name: metrics
        containerPort: 11888
        protocol: TCP
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "11888"
      prometheus.io/path: "/metrics/prometheus"
```

Declaring `ports` is what makes the pods discoverable. Pod discovery creates one target per declared
container port, and a pod that declares none is discovered at its pod IP with no port at all. Scrape
configurations that build the address from the `prometheus.io/port` annotation work either way, but
the ones that match that annotation against the pod's declared ports drop the pod when there is
nothing to match.

The DaemonSet runs on the host network. Widening `httpServerBinding` past `127.0.0.1` exposes
`/metrics/prometheus` — along with `/healthz` and `/readyz` — on every node's IP. Restrict access at
the node level (a host firewall, or your CNI's host-endpoint policy): an ordinary pod-selector
NetworkPolicy does not reliably cover host-network pods, because most CNIs treat traffic to the node
IP as node traffic rather than pod traffic.

Kubernetes also defaults `hostPort` to `containerPort` for host-network pods, so declaring `11888`
claims it on every node, and a collision leaves the pod `Pending` rather than failing at bind time.
If you run a [second Collectord deployment](#secondary-collectord-deployment) on the same nodes,
give it its own port in `httpServerBinding` — its probes and its addon follow that port — and use
the same port in its `ports` and `prometheus.io/port` annotation.

The liveness and readiness probes keep working unchanged: they reach the server on `127.0.0.1`, which
`0.0.0.0` still covers.

#### Counting the events and bytes leaving each pipeline

`[pipe.eventcount]` adds two more counters to the metrics above, `pipeline_events` and
`pipeline_bytes`, labelled by where each event goes. It is off until you enable it:

```yaml
collectord:
  configuration:
    pipeEventCount:
      disabled: false
      labels: [index, sourcetype, output]
      fields: [kubernetes_namespace]
      maxSeries: 1000
```

`disabled: false` is what turns it on; the rest are optional. `labels` takes any of `index`,
`sourcetype`, `source`, `host` and `output`, and defaults to `index, sourcetype, output` when
you set neither it nor `fields`. `fields` takes event fields, such as `kubernetes_namespace`.
Every combination of label values is two metric series, and `maxSeries` bounds the
combinations — past it the rest are counted under `other`, so totals stay correct while
per-combination detail is folded together. `0` uses Collectord's own default of 1000.

Collectord can also forward these counters to your output, as one event per series per
interval from every node. That is off by default; add `^pipeline_events$` and
`^pipeline_bytes$` to `configuration.inputs.collectordMetrics.whitelist` to turn it on.
Helm replaces a list rather than merging it, so copy the chart's default list into your
values first and add to it: a list of your own replaces every default entry, and the monitoring
app's Collectord metrics dashboard and its Collectord alerts read those.

#### Scraping with Prometheus 3

`/metrics/prometheus` answers with `Content-Type: text/plain; version=0.0.4; charset=utf-8`, the
Prometheus text exposition format, so Prometheus 2 and Prometheus 3 both scrape it with no extra
configuration.

Collectord 26.04.4 and earlier answered with `Content-Type: application/text`, which is not a valid
media type. Prometheus 2 fell back to its text parser and scraped those versions anyway;
Prometheus 3 discovers the target and then marks it down with

```
received unsupported Content-Type "application/text" and no fallback_scrape_protocol specified for target
```

even though the endpoint is healthy and `curl` returns metrics. Forwarding to the output is not
affected — only the scrape of Collectord's own metrics. Upgrading Collectord fixes it; until
you can, tell the scraper which protocol to assume:

```yaml
# Prometheus scrape_config
fallback_scrape_protocol: PrometheusText0.0.4
```

```yaml
# Prometheus Operator ServiceMonitor / PodMonitor
spec:
  fallbackScrapeProtocol: PrometheusText0.0.4
```

Prometheus uses that protocol only when a response's Content-Type is missing or unsupported, so the
setting can stay in place while you upgrade.

`httpServerEndpoints.pprof` stays off. Leave it that way unless support asks you for a profile.

## Support

Please refer to [How to submit a support request?](https://www.outcoldsolutions.com/docs/faq/#how-to-submit-a-support-request)

## License

[OUTCOLD SOLUTIONS SOFTWARE LICENSE AGREEMENT](https://www.outcoldsolutions.com/legal/license-agreement/)
