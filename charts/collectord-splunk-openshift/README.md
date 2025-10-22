# Collectord Helm Charts for Monitoring OpenShift in Splunk Enterprise and Splunk Cloud

This helm chart provides a way to deploy Collectord in OpenShift clusters for monitoring OpenShift in Splunk Enterprise and Splunk Cloud.
Please refer to the documentation on how to install Monitoring OpenShift application in Splunk [here](https://www.outcoldsolutions.com/docs/monitoring-openshift/).

## Prerequisites

- OpenShift 4.11+
- Helm 3.8+

## Getting Started

At this point we assume that you have installed Monitoring OpenShift application in Splunk, and enabled Splunk HTTP Event Collector (HEC). Please refer to
[Monitoring OpenShift - Installation](https://www.outcoldsolutions.com/docs/monitoring-openshift/installation/) on how to do that.

Review and accept [license agreement](https://www.outcoldsolutions.com/docs/license-agreement/). If your organization has not purchased a license, 
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
    oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift > collectorforopenshift.yaml
```

To install the chart, run the following command:

```bash
helm install collectorforopenshift \
    --namespace collectorforopenshift \
    --create-namespace \
    -f my_values.yaml \
    oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift
```

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
    oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift
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
    oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift
```

Secondary we will create a configuration file for Splunk Cloud `splunkcloud_values.yaml`, where we will call this deployment
`collectorforopenshift-cloud`, and reference already created objects like service account, priority class, and cluster role,
created with previous deployment.
For example:

```yaml
collectord:
  serviceAccount:
    create: false
    name: collectorforopenshift
  
  priorityClass:
    create: false
    name: collectorforopenshift-critical
    
  clusterRole:
    create: false
    name: collectorforopenshift
  
  configuration:
    general: 
      annotationsSubdomain: 'splunkcloud'
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

To deploy it, you will run command, where we reference the same namespace (and ClusterRole, ClusterRoleBinding, ServiceAccount), but create separate DaemonSet, StatefulSets and Deployments specifically for the Splunk Cloud deployment.

```bash
helm install collectorforopenshift-cloud \
    --namespace collectorforopenshift \
    -f splunkcloud_values.yaml \
    oci://registry-1.docker.io/outcoldsolutions/collectord-splunk-openshift
```

## Support

Please refer to [How to submit a support request?](https://www.outcoldsolutions.com/docs/faq/#how-to-submit-a-support-request)

## License

[OUTCOLD SOLUTIONS SOFTWARE LICENSE AGREEMENT](https://www.outcoldsolutions.com/docs/license-agreement/)