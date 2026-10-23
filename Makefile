# Publishing by hand, for a chart-only release: a Collectord release publishes its charts itself.
OCI_REGISTRY=registry-1.docker.io/outcoldsolutions
# ghcr.io keeps the charts under charts/: its top-level names are the images'.
GHCR_OCI_REGISTRY=ghcr.io/outcoldsolutions/charts

chart_version = $(shell grep version charts/$(1)/Chart.yaml | head -n 1 | grep -Eo "[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+")

# Push to Docker Hub, then copy that manifest to ghcr.io byte for byte: a second
# helm push would stamp its own created annotation, so the digests would differ.
# Needs a ghcr.io login with write:packages (gh auth token | oras login ghcr.io
# --username <user> --password-stdin).
define chart_publish
	@helm push dist/$(1)-$(call chart_version,$(1)).tgz oci://${OCI_REGISTRY}
	@oras cp ${OCI_REGISTRY}/$(1):$(call chart_version,$(1)) ${GHCR_OCI_REGISTRY}/$(1):$(call chart_version,$(1))
endef

collectord:
	@helm lint charts/collectord
	@helm package charts/collectord -d dist/
collectord-publish: collectord
	$(call chart_publish,collectord)
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
	$(call chart_publish,collectord-elasticsearch)
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
	$(call chart_publish,collectord-opensearch)
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
	$(call chart_publish,collectord-splunk-kubernetes)
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
	$(call chart_publish,collectord-splunk-openshift)
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
	$(call chart_publish,collectord-syslog)
collectord-syslog-artifacthub-repo.yml:
	oras push \
        ${OCI_REGISTRY}/collectord-syslog:artifacthub.io \
        --config /dev/null:application/vnd.cncf.artifacthub.config.v1+yaml \
        charts/collectord-syslog/artifacthub-repo.yml:application/vnd.cncf.artifacthub.repository-metadata.layer.v1.yaml

all-publish: collectord-publish collectord-elasticsearch-publish collectord-opensearch-publish collectord-splunk-kubernetes-publish collectord-splunk-openshift-publish collectord-syslog-publish
