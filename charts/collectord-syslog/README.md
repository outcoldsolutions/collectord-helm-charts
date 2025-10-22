# Collectord Helm Charts for Monitoring OpenShift with Syslog (QRadar)

This helm chart provides a way to deploy Collectord in OpenShift clusters for monitoring OpenShift with Syslog (QRadar)
Please refer to the documentation about how to forward logs to Syslog (QRadar) [here](https://www.outcoldsolutions.com/docs/syslog-kubernetes/).

## Prerequisites

- Kubernetes 1.24+
- Helm 3.8+

## Getting Started

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

## Support

Please refer to [How to submit a support request?](https://www.outcoldsolutions.com/docs/faq/#how-to-submit-a-support-request)

## License

[OUTCOLD SOLUTIONS SOFTWARE LICENSE AGREEMENT](https://www.outcoldsolutions.com/docs/license-agreement/)