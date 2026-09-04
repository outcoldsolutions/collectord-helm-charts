# Collectord Helm Charts for Monitoring OpenShift with Syslog (QRadar)

This helm chart provides a way to deploy Collectord in OpenShift clusters for monitoring OpenShift with Syslog (QRadar)
Please refer to the documentation about how to forward logs to Syslog (QRadar) [here](https://www.outcoldsolutions.com/docs/syslog-kubernetes/).

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+

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
        cluster: 'dev'
    outputs:
      syslog:
        default: 
          address: "192.168.1.100:514"
```

Where you will agree to the license agreement, include your license key, and configure syslog default output. 

You can generate a YAML file for deployment using the following command:

```bash
helm template collectorforkubernetes-syslog \
    --namespace collectorforkubernetes-syslog \
    --create-namespace \
    --include-crds \
    -f my_values.yaml \
    oci://registry-1.docker.io/outcoldsolutions/collectord-syslog > collectorforkubernetes-syslog.yaml
```

To install the chart, run the following command:

```bash
helm install collectorforkubernetes-syslog \
    --namespace collectorforkubernetes-syslog \
    --create-namespace \
    -f my_values.yaml \
    oci://registry-1.docker.io/outcoldsolutions/collectord-syslog
```

## Configuration

Collectord is configured using the `ini` file format. You can find a reference with all possible configurations [here](https://www.outcoldsolutions.com/docs/monitoring-openshift/reference/).
This helm chart allows you to customize and override those configurations.
Using `my_values.yaml` as a template, you can customize the configuration to suit your needs. Please refer to the [./values.yaml](./values.yaml) for default configuration and possible values.

### Using secrets

If you want to store some configurations in a secret, first you need to create a secret with the `ini` format, that Collectord can read from. For example, if we want to store license in the secret file,
first we will create a secret file with the `ini` format and `.conf` extension with name `101-general.conf`.

```ini
[general]
license = <your_license_key>
```

Using this file we can create a secret using the `ini` file:

```bash
kubectl create namespace collectorforkubernetes-syslog
kubectl create secret generic collectord-secret \
  --from-file=101-general.conf=101-general.conf \
  -n collectorforkubernetes-syslog
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
      syslog:
        default: 
          address: "192.168.1.100:514"
```

And install it using the following command (don't need to create namespace as we already created it):

```bash
helm install collectorforkubernetes-syslog \
    --namespace collectorforkubernetes-syslog \
    -f my_values.yaml \
    oci://registry-1.docker.io/outcoldsolutions/collectord-syslog
```

> NOTE: Collectord reads all files with `.conf` extension from the `/config` directory and subdirectories. It will sort them by name in ascending order before reading them.
> In a case of file names `001-general.conf` and `101-general.conf`, all values in `101-general.conf` will override values in `001-general.conf`.

### Collecting Collectord's own metrics

Collectord serves its internal metrics in Prometheus format on `/metrics/prometheus`, from the same
internal http server that serves the health probes. This chart ships that server switched off
(`httpServerBinding: ""`). To let Prometheus collect the metrics, bind the server on an address the
scraper can reach, enable the metrics endpoint, declare the port on each workload, and annotate the
pods:

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

  daemonsetMaster:
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

Both DaemonSets run on the host network, so binding the server exposes `/metrics/prometheus` — along
with `/healthz` and `/readyz` — on every node's IP. Restrict access at the node level (a host
firewall, or your CNI's host-endpoint policy): an ordinary pod-selector NetworkPolicy does not
reliably cover host-network pods, because most CNIs treat traffic to the node IP as node traffic
rather than pod traffic.

Kubernetes also defaults `hostPort` to `containerPort` for host-network pods, so declaring `11888`
claims it on every node, and a collision leaves the pod `Pending` rather than failing at bind time.
If you run a second Collectord deployment on the same nodes, give its DaemonSets their own port in
both `httpServerBinding` and `ports`. The addon runs off the host network, so it keeps port `11888`
either way.

Setting a binding also turns on `/healthz` and `/readyz`, which are enabled by default. This chart
defines no probes, so nothing depends on them until you add some.

#### Known issue: Prometheus 3 marks the target down

Collectord serves `/metrics/prometheus` with `Content-Type: application/text`, which Prometheus 3
rejects. The target is discovered and then marked down with

```
received unsupported Content-Type "application/text" and no fallback_scrape_protocol specified for target
```

even though the endpoint is healthy and `curl` returns metrics. Prometheus 2 silently fell back to
its classic text parser, which is why this went unnoticed. Forwarding to the output is never
affected — only the scrape of Collectord's own metrics.

Until a release ships the corrected header, tell the scraper which protocol to assume:

```yaml
# Prometheus scrape_config
fallback_scrape_protocol: PrometheusText0.0.4
```

```yaml
# Prometheus Operator ServiceMonitor / PodMonitor
spec:
  fallbackScrapeProtocol: PrometheusText0.0.4
```

`httpServerEndpoints.pprof` stays off. Leave it that way unless support asks you for a profile.

## Support

Please refer to [How to submit a support request?](https://www.outcoldsolutions.com/docs/faq/#how-to-submit-a-support-request)

## License

[OUTCOLD SOLUTIONS SOFTWARE LICENSE AGREEMENT](https://www.outcoldsolutions.com/legal/license-agreement/)