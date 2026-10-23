# Collectord Helm Charts for Monitoring Kubernetes in Elasticsearch

This helm chart provides a way to deploy Collectord in Kubernetes clusters for monitoring Kubernetes in Elasticsearch.
Please refer to the documentation on about the solution [here](https://www.outcoldsolutions.com/docs/elasticsearch-kubernetes/).

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+

## Pod security

The DaemonSet reads the node's filesystem, journal and cgroup tree through a host mount, runs
on the host network and is privileged. Under Pod Security Admission the namespace they install
into has to admit privileged pods; a namespace that enforces `baseline` or `restricted` rejects
them at admission:

```bash
kubectl label namespace collectorforkubernetes-elasticsearch pod-security.kubernetes.io/enforce=privileged
```

The addon Deployment (the cluster-wide watcher for events, objects and annotated Prometheus
endpoints) runs without privileges, capabilities or privilege escalation and under the runtime's
default seccomp profile (`collectord.deployment.securityContext`). It runs as root, and on
SELinux-enforcing nodes in the `spc_t` domain, only to read the state directory it shares with
the DaemonSet on its node: a hostPath the DaemonSet writes as root, which is never relabeled.

The ClusterRole grants read access to the objects Collectord attaches as metadata and
`nodes/metrics`, which authorizes a direct scrape of a kubelet's `/metrics`. It does not grant
`nodes/proxy`: that subresource is only needed to reach the kubelet through the API server's node
proxy, which none of this chart's inputs use, and a `get` on it is enough to exec into any pod on
the node. If you add a kubelet scrape through the proxy path in your values, add `nodes/proxy`
under `collectord.clusterRole.rules`; the direct scrape is recommended.

It grants nothing at all on `secrets`: the only feature that reads one is a `SplunkOutput`
resource reading its HEC token from a Secret, and this chart configures no Splunk output. Set
`collectord.clusterRole.userOutputSecrets: true` if you add one and want that. If you add an
`[input.kubernetes_watch::...]` section with `kind = Secret`, add `get`, `list` and `watch` on
`secrets` under `collectord.clusterRole.rules`; cluster-wide those verbs return the contents of
every Secret in the cluster, so prefer a namespace-scoped watch and Role where you can.

The DaemonSet runs under the built-in `system-node-critical` PriorityClass and the addon Deployment
under `system-cluster-critical`: the kubelet never evicts pods of these classes, and while a node is
under disk pressure it admits no other, so a node whose disk fills keeps reporting. A new addon pod
(an upgrade, a deleted pod) still waits for a node without disk pressure: the scheduler places a pod
on one only if it tolerates the `node.kubernetes.io/disk-pressure` taint, as the DaemonSet's do. A
cluster can limit these classes to namespaces holding a ResourceQuota scoped to them, as GKE
Standard does; the chart renders one in the release namespace
(`collectord.priorityClass.resourceQuota`). With it set to `false`, GKE Standard refuses the pods: a
new install starts none, an upgrade from 26.04 takes Collectord off one node and stops there, and
`helm` without `--wait` reports success either way. To run both workloads under a class the chart creates
instead, as releases before 26.10.1 did, set `collectord.priorityClass.name`
(`collectorforkubernetes-elasticsearch-critical` is the class those releases created);
`collectord.priorityClass.create: false` names a class that exists already, that one when no name is
set.

## Getting Started

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
        "orchestrator.cluster.name": 'dev'
    outputs:
      elasticsearch:
        default:
          host: 'https://elasticsearch:9200'
          authorizationBasicUsername: elastic
          authorizationBasicPassword: elastic
          insecure: true
```

Where you will agree to the license agreement, include your license key, and configure Elasticsearch output. 

You can generate a YAML file for deployment using the following command:

```bash
helm template collectorforkubernetes-elasticsearch \
    --namespace collectorforkubernetes-elasticsearch \
    --create-namespace \
    --include-crds \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-elasticsearch > collectorforkubernetes-elasticsearch.yaml
```

To install the chart, run the following command:

```bash
helm install collectorforkubernetes-elasticsearch \
    --namespace collectorforkubernetes-elasticsearch \
    --create-namespace \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-elasticsearch
```

The chart and Collectord's image come from `registry.outcold.solutions`, whose pulls also reach
`ghcr.io` and `pkg-containers.githubusercontent.com`: where egress is filtered, allow all three.
Docker Hub has the same chart, `oci://registry-1.docker.io/outcoldsolutions/collectord-elasticsearch`,
and the same images: to pull the image from there, set
`collectord.image.repository: docker.io/outcoldsolutions/collectorforkubernetes`.

To pin the image by digest, set `collectord.image.digest` to the `sha256:` digest of the tag you pull;
the tag then only labels it. Look the digest up with
`docker buildx imagetools inspect registry.outcold.solutions/outcoldsolutions/collectorforkubernetes:<tag>`
(the `Digest:` line). The FIPS tag has a digest of its own.

## Configuration

Collectord is configured using the `ini` file format. You can find a reference with all possible configurations [here](https://www.outcoldsolutions.com/docs/elasticsearch-kubernetes/configuration/opensearch/).
This helm chart allows you to customize and override those configurations.
Using `my_values.yaml` as a template, you can customize the configuration to suit your needs. Please refer to the [./values.yaml](./values.yaml) for default configuration and possible values.

### Using secrets

If you want to store some configurations in a secret, first you need to create a secret with the `ini` format, that Collectord can read from. For example, if we want to store license, and token in secret file,
first we will create a secret file with the `ini` format and `.conf` extension with name `101-general.conf`.

```ini
[general]
license = <your_license_key>

[output.elasticsearch]
authorizationBasicUsername = elastic
authorizationBasicPassword = elastic
```

Using this file we can create a secret using the `ini` file:

```bash
kubectl create namespace collectorforkubernetes-elasticsearch
kubectl create secret generic collectord-secret \
  --from-file=101-general.conf=101-general.conf \
  -n collectorforkubernetes-elasticsearch
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
        "orchestrator.cluster.name": 'dev'
    outputs:
      elasticsearch:
        default:
          host: 'https://elasticsearch:9200'
          insecure: true
```

And install it using the following command (don't need to create namespace as we already created it):

```bash
helm install collectorforkubernetes-elasticsearch \
    --namespace collectorforkubernetes-elasticsearch \
    -f my_values.yaml \
    oci://registry.outcold.solutions/outcoldsolutions/charts/collectord-elasticsearch
```

> NOTE: Collectord reads all files with `.conf` extension from the `/config` directory and subdirectories. It will sort them by name in ascending order before reading them.
> In a case of file names `001-general.conf` and `101-general.conf`, all values in `101-general.conf` will override values in `001-general.conf`.

### Collecting Collectord's own metrics

Collectord serves its internal metrics in Prometheus format on `/metrics/prometheus`, from the same
internal http server that serves the health probes. This chart already runs that server for the
probes, on `127.0.0.1:11891`, with only the `/healthz` and `/readyz` endpoints enabled. The port is
its own because every chart runs its DaemonSet on the host network and this one can share nodes with
the Collectord for Splunk charts (`11888`, and `11889` for a second Splunk release) and the OpenSearch
chart (`11892`). To let
Prometheus collect the metrics, enable that endpoint too, widen the bind address so the scraper can
reach it, declare the port on each workload, and annotate the pods:

```yaml
collectord:
  configuration:
    general:
      httpServerBinding: "0.0.0.0:11891"
      "httpServerEndpoints.metrics": true

  daemonset:
    ports:
      - name: metrics
        containerPort: 11891
        protocol: TCP
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "11891"
      prometheus.io/path: "/metrics/prometheus"

  deployment:
    ports:
      - name: metrics
        containerPort: 11891
        protocol: TCP
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/port: "11891"
      prometheus.io/path: "/metrics/prometheus"
```

Declaring `ports` is what makes the pods discoverable. Pod discovery creates one target per declared
container port, and a pod that declares none is discovered at its pod IP with no port at all. Scrape
configurations that build the address from the `prometheus.io/port` annotation work either way, but
the ones that match that annotation against the pod's declared ports drop the pod when there is
nothing to match.

The DaemonSet runs on the host network, so binding the server exposes `/metrics/prometheus` — along
with `/healthz` and `/readyz` — on every node's IP. Restrict access at the node level (a host
firewall, or your CNI's host-endpoint policy): an ordinary pod-selector NetworkPolicy does not
reliably cover host-network pods, because most CNIs treat traffic to the node IP as node traffic
rather than pod traffic.

Kubernetes also defaults `hostPort` to `containerPort` for host-network pods, so declaring `11891`
claims it on every node, and a collision leaves the pod `Pending` rather than failing at bind time.
If you run a second Collectord deployment on the same nodes, give it its own port in
`httpServerBinding` — its probes and its addon follow that port — and use the same port in its `ports` and
`prometheus.io/port` annotation.

The liveness and readiness probes keep working unchanged: they reach the server on `127.0.0.1`,
which `0.0.0.0` still covers.

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