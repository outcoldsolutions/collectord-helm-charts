OCI_REGISTRY=registry-1.docker.io/outcoldsolutions

collectord:
	@helm lint charts/collectord
	@helm package charts/collectord -d dist/
collectord-publish: collectord
	@helm push dist/collectord-$(shell cat charts/collectord/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

collectord-elasticsearch:
	@helm dependency update charts/collectord-elasticsearch
	@helm lint charts/collectord-elasticsearch
	@helm package charts/collectord-elasticsearch -d dist/
collectord-elasticsearch-publish: collectord-elasticsearch
	@helm push dist/collectord-elasticsearch-$(shell cat charts/collectord-elasticsearch/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-elasticsearch-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-elasticsearch:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-elasticsearch/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

collectord-opensearch:
	@helm dependency update charts/collectord-opensearch
	@helm lint charts/collectord-opensearch
	@helm package charts/collectord-opensearch -d dist/
collectord-opensearch-publish: collectord-opensearch
	helm push dist/collectord-opensearch-$(shell cat charts/collectord-opensearch/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-opensearch-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-opensearch:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-opensearch/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

collectord-splunk-kubernetes:
	@helm dependency update charts/collectord-splunk-kubernetes
	@helm lint charts/collectord-splunk-kubernetes
	@helm package charts/collectord-splunk-kubernetes -d dist/
collectord-splunk-kubernetes-publish: collectord-splunk-kubernetes
	@helm push dist/collectord-splunk-kubernetes-$(shell cat charts/collectord-splunk-kubernetes/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-splunk-kubernetes-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-splunk-kubernetes:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-splunk-kubernetes/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

collectord-splunk-openshift:
	@helm dependency update charts/collectord-splunk-openshift
	@helm lint charts/collectord-splunk-openshift
	@helm package charts/collectord-splunk-openshift -d dist/
collectord-splunk-openshift-publish: collectord-splunk-openshift
	@helm push dist/collectord-splunk-openshift-$(shell cat charts/collectord-splunk-openshift/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-splunk-openshift-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-splunk-openshift:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-splunk-openshift/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

collectord-syslog:
	@helm dependency update charts/collectord-syslog
	@helm lint charts/collectord-syslog
	@helm package charts/collectord-syslog -d dist/
collectord-syslog-publish: collectord-syslog
	@helm push dist/collectord-syslog-$(shell cat charts/collectord-syslog/Chart.yaml | grep version | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+").tgz  oci://${OCI_REGISTRY}
collectord-syslog-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-syslog:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-syslog/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

all-publish: collectord-publish collectord-elasticsearch-publish collectord-opensearch-publish collectord-splunk-kubernetes-publish collectord-splunk-openshift-publish collectord-syslog-publish