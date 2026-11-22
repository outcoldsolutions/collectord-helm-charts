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

## Uninstalling

```bash
helm uninstall collectorforopenshift --namespace collectorforopenshift
```

`helm uninstall` leaves the chart's SecurityContextConstraints in the cluster: the chart
installs it as a Helm hook, and Helm does not remove hook resources. It admits privileged pods
run by the service account `collectorforopenshift` of the release's namespace, and
would admit a service account created under that name later, so delete it as well. It is named
after the release, or `scc.name` when you set one:

```bash
oc delete scc collectorforopenshift
```

The custom resource definitions (`configurations.collectord.io` and `splunkoutputs.collectord.io`)
stay too, as Helm never deletes a chart's CRDs. Delete them only when no other Collectord release
is left in the cluster: deleting a definition deletes every object of that kind.

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

### Sending events over Splunk-to-Splunk (S2S)

`outputs.s2s` sends events and metrics-index records to the indexers' receiving port (a `splunktcp`
input, `splunktcp-ssl` for `tls://`) with the protocol Splunk forwarders use, instead of to HTTP
Event Collector. The indexers must run Splunk 9.1 or later. Make it the default output, or name it
(`s2s`, `s2s::<name>`) in an input's `output` or `metricsOutput`; the HEC output (`outputs.splunk`)
can stay beside it. Indexer acknowledgements are always on: an event is acknowledged to its source
only once an indexer confirmed it, and whatever a connection carried when it ended is sent again
(and may be indexed twice: Splunk does not deduplicate). Each thread holds one connection and moves
to the next url every `loadBalanceFrequency`.

The S2S output is in beta in 26.10.2.

```yaml
collectord:
  configuration:
    general:
      defaultOutput: s2s
    outputs:
      s2s:
        default:
          url: 'tls://idx1.example.com:9998'
          urls:
          - 'tls://idx2.example.com:9998'
          # the forwarder token of the indexers' [splunktcptoken://...] stanza, if they have one
          token: ''
          defaultIndex: 'openshift'
          defaultMetricsIndex: 'openshift_metrics'
```

| Key | Default | |
| --- | --- | --- |
| `url`, `urls` | | `tcp://host:port` or `tls://host:port` |
| `urlSelection` | `random` | `random`, `round-robin` (each thread starts on its own url) or `random-with-round-robin` (a random start, then the next url): where a thread starts and moves to |
| `token` | | the forwarder token of the indexers' `[splunktcptoken://...]` stanza |
| `insecure`, `minTLSVersion`, `maxTLSVersion`, `tlsCipherSuites`, `tlsCurvePreferences`, `caPath`, `caName`, `clientCertPath`, `clientKeyPath` | `false`, the rest empty | TLS for `tls://` urls, as on `outputs.splunk`; a client certificate for an input with `requireClientCert` |
| `frequency` | `5s` | how often a thread sends what it holds |
| `batchSize` | `768K` | the bytes of one batch, as they go on the wire |
| `events` | `0` | the events of one batch; `0` leaves it to `batchSize` |
| `threads`, `threadsAlgorithm` | `2`, `weighted` | connections per Collectord instance, and how pipelines share them |
| `excludeFields` | `[]` | fields left out of every event, as on `outputs.splunk`: a list of names (`[openshift_pod_ip]`), or the conf's map (`{openshift_pod_ip: true}`); on a named output a `false` entry keeps a field the main output leaves out |
| `queueSize` | `1024` | as on `outputs.splunk` |
| `ackTimeout` | `5m` | how long a batch waits for its acknowledgement before the connection is given up and the batch sent again; 5s at least |
| `connectTimeout` | `20s` | a connect: TCP, TLS and the S2S handshake; 1s at least |
| `writeTimeout` | `5m` | each write: an indexer whose queues are blocked stops reading, and a write given up sooner sends its batches again to another while it still indexes them; `frequency` at least |
| `backoffOnFailure` | `30s` | how long an indexer whose connect failed is tried after the others, and how long one that ended a new connection before acknowledging anything (a refused `token`) is not connected to at all; doubled with each failure in a row up to ten times; 1s at least |
| `loadBalanceFrequency` | `30s` | how long a connection takes batches before the thread moves to the next url; 1s at least |
| `idleTimeout` | `frequency` × 10 | closes a connection nothing went through for this long; `frequency` at least |
| `channelIdleTimeout` | `idleTimeout` | closes a channel (one source, host and sourcetype) unused for this long; `frequency` at least |
| `maxChannels` | `0`: the indexer's `channel_limit` | the channels one connection holds open; 2 at least, one is the info event's |
| `compression` | `false` | zlib, as a forwarder's `compressed = true`: an eighteenth of the bytes for logs, an eleventh for metrics, for more of Collectord's CPU (still less than HEC's) |
| `shutdownTimeout` | `5s` | how long a shutdown waits for owed acknowledgements; keep it within the pod's `terminationGracePeriodSeconds`; 1s at least |
| `loadBalanceVolume` | `0`: by time alone | the bytes after which a connection moves to the next url |
| `dnsResolutionInterval` | `5m` | every address a url's host name resolves to is an indexer (a headless Service spreads over its pods), resolved again this often; 10s at least |
| `proxyUrl` | | a SOCKS5 proxy, `socks5://[user:password@]host:port`, or `socks5h://` for the proxy to resolve the names; an HTTP proxy cannot carry S2S |
| `indexerDiscovery.managerUrl` | | a cluster manager's `https://cm:8089`: the indexers it names join `url` and `urls`, which may be empty; an SSL one is verified against `caName`, else the address the manager names. The manager is asked through `proxyUrl` when that is set. A named output that sets `url`, `urls` or this key takes none of the three from the main output, nor its manager credentials |
| `indexerDiscovery.token`, `.username`, `.password` | | a Splunk identity on the manager (any role); a forwarder's `pass4SymmKey` is not supported |
| `indexerDiscovery.site`, `.failover` | `default`, `true` | the indexers' site, and its failover targets when it has none Up |
| `indexerDiscovery.insecure`, `.caPath`, `.caName` | `false`, none, none | TLS for the manager's https |
| `defaultIndex` | | the index of an event whose input names none |
| `defaultMetricsIndex` | | the index of a metrics-index record that names none |
| `duplicateFieldsWithUnderscore`, `requireExplicitIndex`, `maximumMessageLength`, `includeEventID`, `timestampPrecision` | `false`, `false`, none, `false`, `3` | as on `outputs.splunk` |
| `continuesFrom` | | the output this one replaced for the same Splunk (`splunk`, `splunk::<name>`): a log it holds no position for continues from that output's; never inherited by a named output |

- No token supplies a default index over S2S: without `defaultIndex` and `defaultMetricsIndex`
  such records land in the `splunktcp` input's index (`main`).
- An event for an index the indexers do not have is acknowledged and dropped: nothing over S2S
  tells Collectord, and `incorrectIndexBehavior` is HEC's. The indexer logs `Received event for
  unconfigured/disabled/deleted index` in `_internal`; `lastChanceIndex` in the indexers'
  `indexes.conf` keeps such events in an index of your choice.
- A metrics index keeps whole seconds unless it sets `metric.timestampResolution = ms`.
- Without `compression`, S2S sends 13 to 16 times the bytes of HTTP Event Collector's gzip for
  logs, 7 times for metrics; with it, a quarter fewer than HEC's for logs (about 100 bytes an
  event) and fewer for metrics, for half again Collectord's CPU on the output, still below HEC's.
  Turn it on across a WAN, a VPN or a metered link.
- A proxy is SOCKS5 (`proxyUrl`): an HTTP proxy cannot carry S2S, a TCP stream.
- Index-time props on the indexers (`SEDCMD`, `TRANSFORMS`) run on these events as on HEC events.
- An indexer that stops or restarts says so on its connections, and Collectord leaves it at once,
  as a forwarder with `useACK` does: what each connection had unacknowledged is sent again and may
  be indexed twice. As it stops, the indexer logs these ERRORs for the connections it ends, a
  forwarder's too, and they are expected: `there was an error writing data to storage` and
  `Encountered S2S Exception='Client is unable to process ACKs' … Terminating client connection`.
  A cluster peer's `splunk offline` sends no notice: it closes the connections about 3 s in, and
  Collectord sends again what they had unacknowledged ("ended with … events unacknowledged", a
  WARN), which may be indexed twice too.
- With another default output, `outputs.splunk` without a url is no output. `SplunkOutput`
  objects need it configured: they are HEC endpoints.
- `outputs.s2s.default` renders without a url too when a named S2S output is set, which takes
  what it leaves unset from it, and with `defaultOutput: s2s`, for a url and token kept in a
  mounted Secret (see "Using secrets") beside the TLS keys set here.

#### Switching from HEC

1. Set `defaultIndex` and `defaultMetricsIndex` on `outputs.s2s.default` first: no HEC token
   supplies an index over S2S, and without them records land in the `splunktcp` input's index.
2. Set `general.defaultOutput` to `s2s` (or an input's `output` from `splunk::<name>` to
   `s2s::<name>`) at a quiet moment: the upgrade restarts the pods, and the batches in flight then
   are sent again.
3. Set `continuesFrom: splunk` on `outputs.s2s.default` (`splunk::<name>` on `outputs.s2s.<name>`)
   when S2S replaces HEC for the same Splunk: every log file and journal then continues where HEC's
   acknowledgements left it. Without it the S2S output reads the logs as a new output does (a live
   file from its start, unless a dry run to `devnull` left a position), which is right for another
   Splunk, and Collectord says so at startup. A container
   still sent to HEC as well (`collectord.io/logs-output: splunk,s2s`) never takes HEC's positions,
   nor does a volume-log configuration while another of the pod's sends to HEC. Switching
   back finds HEC's own positions from before the switch, so what S2S sent since is sent again.

```yaml
collectord:
  configuration:
    general:
      defaultOutput: s2s
    outputs:
      s2s:
        default:
          url: tls://indexer1.example.com:9998
          defaultIndex: openshift
          defaultMetricsIndex: openshift_metrics
          continuesFrom: splunk
```

`continuesFrom` is on `outputs.splunk` too, for an HEC output that replaced another
(`splunk::compliance` after `splunk::audit`).

A Collectord release before the S2S output does not start with `defaultOutput: s2s` (unknown
output): roll the values back with the release.

#### Coming from outputs.conf

| outputs.conf (`[tcpout]`, `[tcpout:<group>]`) | `outputs.s2s` |
| --- | --- |
| `server` | `url`, `urls` (`tcp://` or `tls://` each) |
| `autoLBFrequency` | `loadBalanceFrequency` |
| `autoLBVolume` | `loadBalanceVolume` |
| `useACK` | always on |
| `readTimeout` | `ackTimeout` |
| `connectionTimeout` | `connectTimeout` |
| `writeTimeout` | `writeTimeout` |
| `backoffOnFailure` | `backoffOnFailure`, doubled with each failure in a row |
| `ackTimeoutOnShutdown` | `shutdownTimeout` |
| `compressed` | `compression` |
| `token` | `token` |
| `dnsResolutionInterval` | `dnsResolutionInterval` |
| `socksServer`, `socksUsername`, `socksPassword`, `socksResolveDNS` | `proxyUrl`: `socks5://user:password@host:port`, `socks5h://` to resolve at the proxy |
| `sslRootCAPath`, `clientCert`, `sslVerifyServerCert`, `sslCommonNameToCheck`, `sslAltNameToCheck` | `caPath`; `clientCertPath` and `clientKeyPath` (an unencrypted key); `insecure`; `caName` sets the name verified and sent |
| `sslVersions`, `cipherSuite`, `ecdhCurves` | `minTLSVersion`, `maxTLSVersion`, `tlsCipherSuites`, `tlsCurvePreferences` |
| `channelTTL`, `channelReapInterval` | `channelIdleTimeout`; idle channels are swept every 10 s (half `channelIdleTimeout` when that is shorter), no key; the channel limit is the indexer's, or `maxChannels` |
| `indexerDiscovery`, `[indexer_discovery:<name>]` | `indexerDiscovery.managerUrl`, with a Splunk token (`indexerDiscovery.token`) or user on the manager instead of `pass4SymmKey`; `indexerDiscovery.site` |
| `forwardedindex.<n>.whitelist` / `blacklist` | not needed: an input names its output and index |
| `maxQueueSize`, persistent queues | not needed: an input keeps its place until the indexer acknowledges, and the output's memory budget bounds what is in flight |
| a server's weight (other senders) | not supported: the urls take turns, a repeated url is one indexer |

Splunk Cloud Platform (not tested against a Cloud stack): its universal forwarder credentials
package names the stack's receivers, `inputs1.<stack>.splunkcloud.com:9997` and on, which go in
`url` and `urls` as `tls://` urls, and carries the CA (`caPath`) and the forwarder's client
certificate and key (`clientCertPath`, `clientKeyPath`). Collectord reads an unencrypted PEM key: a
key the package encrypts with its `sslPassword` needs decrypting first.

### Sending over OTLP

`outputs.otlp` sends logs to `<url>/v1/logs` and metrics to `<url>/v1/metrics` of an OTLP/HTTP
receiver, or with `protocol: grpc` calls an OTLP/gRPC receiver's Export methods: an OpenTelemetry
Collector, or a backend that takes OTLP directly (the table below). Make it the
default output, or name it (`otlp`, `otlp::<name>`) in an input's `output` or `metricsOutput`;
the HEC output (`outputs.splunk`) can stay beside it. An event is
acknowledged to its source once the receiver accepted its batch (a 2xx over HTTP; over gRPC a 200 with `grpc-status: 0`); a refused batch is sent
again, or split down to the record the receiver refuses alone, which is dropped; what a receiver
refused in a batch it stored (a partial success) is counted and not sent again.

The OTLP output is in beta in 26.10.2.

```yaml
collectord:
  configuration:
    general:
      defaultOutput: otlp
    outputs:
      otlp:
        default:
          url: 'http://otel-collector.observability.svc:4318'
          token: ''
          defaultIndex: 'openshift'
          defaultMetricsIndex: 'openshift_metrics'
```

| Key | Default | |
| --- | --- | --- |
| `url` | | the receiver's base: `/v1/logs` and `/v1/metrics` go under its path |
| `logsUrl`, `metricsUrl` | | a signal's endpoint, posted to as is, for a backend whose signals live apart |
| `protocol` | `http` | `grpc` for OTLP/gRPC (HTTP/2: `h2` on `https://`, cleartext on `http://`): the urls name a host and a port and no path (`http://otel-collector.observability.svc:4317`), an `http://` url goes through no HTTP proxy (`https://` or a `socks5://` proxy do), and each of `threads` keeps a connection of its own |
| `signals` | `logs, metrics` | what the output sends; a signal left out is acknowledged and dropped |
| `token` | | sent as `Authorization: Bearer <token>` |
| `headers` | `{}` | request headers, a backend's API key among them (`x-honeycomb-team`, `dd-api-key`) |
| `insecure`, `minTLSVersion`, `maxTLSVersion`, `tlsCipherSuites`, `tlsCurvePreferences`, `caPath`, `caName`, `clientCertPath`, `clientKeyPath` | `false`, the rest empty | TLS, as on `outputs.splunk` |
| `proxyUrl`, `proxyBasicAuth` | | an HTTP proxy, as on `outputs.splunk` |
| `timeout` | `30s` | one request; 1s at least |
| `maxConnAge` | | how long the connections take requests before the output opens new ones, so DNS or a load balancer can pick another receiver; empty or `0` never replaces them by age, 1s at least |
| `frequency` | `5s` | how often a thread sends what it holds |
| `batchSize` | `4M` | the bytes of one batch after compression |
| `rawBatchSize` | `4M`, `3M` under `grpc` | the uncompressed bytes at which a batch seals, before `batchSize`; under `grpc` a receiver refuses a message over 4 MiB uncompressed by default (the Collector's `max_recv_msg_size_mib`) |
| `events` | `0` | the records of one batch; `0` leaves it to the sizes |
| `compression`, `compressionLevel` | `gzip`, the codec's default | `gzip`, which every receiver takes, `zstd`, or `none` |
| `threads`, `threadsAlgorithm` | `1`, round-robin | senders per Collectord instance, and how pipelines share them |
| `queueSize` | `1024` | as on `outputs.splunk` |
| `dedicatedClientPerIndex` | `false` | one batch stream per index; off, one request carries several indexes |
| `defaultIndex`, `defaultMetricsIndex` | `openshift`, `openshift_metrics` | the index of an event, or a metrics-index record, whose input names none: no token supplies one over OTLP. The chart's values set the product's index names; the daemon's own default is none |
| `envelope` | `splunk` | the resource attributes an event's index, source and sourcetype travel as: `splunk` (`com.splunk.index`, `com.splunk.source`, `com.splunk.sourcetype`, what the Collector's Splunk HEC exporter reads), `collectord` (`io.collectord.index`, `io.collectord.source`, `io.collectord.sourcetype`) or `none` |
| `attributes` | `collectord` | the fields' names: Collectord's (`openshift_pod_name`), or `otel`, the OpenTelemetry semantic conventions (`k8s.pod.name`, `k8s.pod.label.<key>`) with `service.name`, `service.namespace`, `service.version` and `service.instance.id` derived as they describe |
| `excludeFields` | `[]` | fields left out, by name in either spelling; under `otel`, also by the name sent; a list or a map, as on `outputs.s2s` |
| `temporality` | `cumulative` | `delta` for a backend that takes only deltas: a monotonic sum or histogram as the change since the series' previous point |
| `metricLabelPrefix` | | before a scraped label's name on a data point; `metric.label.` names it as the Monitoring OpenShift app reads it through a gateway into Splunk |
| `distributions` | `otlp` | how a histogram or summary travels: one OTLP point, or `series`, its classic `_bucket`, `_count`, `_sum` and quantile series as the Splunk output sends them |
| `honorIndexType` | `false` | `true` sends what the Splunk output sends for each input's `indexType` (a sampler's events-index line as a log record), for the app's events-index views behind a gateway |
| `continuesFrom` | | the output this one replaced for the same Splunk through a gateway (`splunk`, `splunk::<name>`): a log it holds no position for continues from that output's; never inherited by a named output |

What each backend needs, from its published documentation:

| Backend | Destination and credentials | Settings |
| --- | --- | --- |
| OpenTelemetry Collector, into Splunk with its Splunk HEC exporter | the Collector's `url` | `envelope: splunk`, `metricLabelPrefix: metric.label.`, `distributions: series`, `honorIndexType: true`: what the Monitoring OpenShift app reads |
| Honeycomb | `url: https://api.honeycomb.io` (EU `https://api.eu1.honeycomb.io`), `headers: {x-honeycomb-team: ...}` | `envelope: none`, `attributes: otel` (`service.name` files the logs by service); metrics land in its managed `Metrics` dataset |
| Datadog | `url: https://otlp.datadoghq.com` (the site's OTLP host), `headers: {dd-api-key: ...}` | `envelope: none`, `attributes: otel`, `temporality: delta` (cumulative is refused), `batchSize: 500KB` (metrics take 512 KiB compressed) |
| New Relic | `url: https://otlp.nr-data.net` (EU `https://otlp.eu01.nr-data.net`), `headers: {api-key: ...}` (the license key) | `envelope: none`, `attributes: otel`, `temporality: delta` (recommended), `rawBatchSize: 800KB` (a request over 1 MB is answered 413 and split), `excludeFields` past 64 resource attributes |
| Grafana Cloud | `url: https://otlp-gateway-<region>.grafana.net/otlp`, `headers: {authorization: Basic <base64 of instance id:token>}` | `envelope: none`, `attributes: otel`, `excludeFields` past 40 resource or 40 metric attributes |
| Dynatrace | `url: https://<environment>.live.dynatrace.com/api/v2/otlp`, `token` (a platform token) | `envelope: none`, `attributes: otel`, `temporality: delta` (cumulative is not ingested); summaries are dropped unless `distributions: series` |
| Splunk Observability Cloud | `metricsUrl: https://ingest.<realm>.observability.splunkcloud.com/v2/datapoint/otlp`, `signals: metrics`, `headers: {x-sf-token: ...}` | `envelope: none`, `attributes: otel`; no OTLP logs endpoint |

- No token supplies a default index over OTLP: without `defaultIndex` and `defaultMetricsIndex`
  a record whose input names none goes without one, and a receiver that wants one refuses it.
- Through a gateway into Splunk an event for an index Splunk does not have is dropped by the
  gateway, with the rest of the request it travelled in when the gateway forwards them
  together: Collectord got its 2xx and counts nothing lost, and `incorrectIndexBehavior` is
  HEC's. Create the indexes the inputs and annotations name before switching.
- Through a gateway into Splunk a dimension with several values (a pod's, namespace's, node's
  or workload's labels, a container's labels) of a metrics-index record arrives as one value
  holding the whole list. The app's dashboards filter and list labels either way; a search of
  your own that names one label exactly (`openshift.pod.labels="app=web"`) matches nothing in the
  metrics index, so match it within the list (`openshift.pod.labels="*app=web*"`).
- A Collectord instance on `outputs.otlp` charts in the app's Collectord metrics view and pages
  through its Alert Catalog templates as one on HEC does, where its own metrics
  (`collectordMetrics`) reach this Splunk: through HEC, or through a gateway with the four
  settings above; its own `otlp_*` series (requests by status, rejected and dropped records,
  points `temporality: delta` held back) are forwarded only when `collectordMetrics.whitelist`
  names them.
- `outputs.otlp.default` renders when it has a `url`, `logsUrl` or `metricsUrl`; without one, when
  a named OTLP output is set, which takes what it leaves unset from it, and with
  `defaultOutput: otlp`, for a url and token kept in a mounted Secret (see "Using secrets").
- With another default output, `outputs.splunk` without a url is no output, and a named
  `outputs.splunk.<name>` beside it still is. `SplunkOutput` objects need `outputs.splunk`
  configured: they are HEC endpoints.
- `collectord verify` posts an empty request to each signal's endpoint (reachability and the
  token), then one record per index the inputs name for it (an index a template resolves is not
  probed); under `envelope: none` one record per signal, since the receiver takes no index. Under
  `protocol: grpc` it says when the url looks like an OTLP/HTTP port (the Collector's 4318).
- An output new to a node reads the logs as a new output does: a live file from its start.
  Switch at a quiet moment, with `continuesFrom: splunk` (`splunk::<name>`) when the receiver
  forwards into the same Splunk the HEC output sent to: the file and journal positions then carry
  over, as they do for `outputs.s2s`; Collectord says at startup when it holds no position while
  the HEC output's are in its database.
- A Collectord release before this output does not start with `defaultOutput: otlp` (unknown
  output): roll the values back with the release.
- Upgrading: a secondary HEC output named `otlp` (`outputs.splunk.otlp`) must be renamed first;
  the OTLP output takes that name, and Collectord refuses to start with both.

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
