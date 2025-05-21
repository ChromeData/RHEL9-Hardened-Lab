.PHONY: help up scan-before harden scan-after delta destroy image image-scan image-gate image-baseline image-control
.DEFAULT_GOAL := help

SSG    := /usr/share/xml/scap/ssg/content/ssg-almalinux9-ds.xml
PROFILE:= xccdf_org.ssgproject.content_profile_stig
SSH    := vagrant ssh -c

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

up: ## Boot the box and install tooling (no hardening yet)
	vagrant up

scan-before: ## OpenSCAP baseline scan -> reports/before.*
	$(SSH) "sudo oscap xccdf eval --profile $(PROFILE) \
		--results /vagrant/reports/before.xml \
		--report  /vagrant/reports/before.html \
		$(SSG) || true"
	@echo "Baseline captured in reports/before.html"

harden: ## Apply the dev-sec hardening roles
	vagrant provision --provision-with ansible
	ANSIBLE_ARGS="--tags harden --skip-tags never" vagrant provision --provision-with ansible || \
		ansible-playbook -i .vagrant/provisioners/ansible/inventory/vagrant_ansible_inventory \
			ansible/site.yml --tags harden

scan-after: ## Re-scan after hardening -> reports/after.*
	$(SSH) "sudo oscap xccdf eval --profile $(PROFILE) \
		--results /vagrant/reports/after.xml \
		--report  /vagrant/reports/after.html \
		$(SSG) || true"
	@echo "Post-hardening captured in reports/after.html"

delta: ## Compute the pass-rate improvement
	python3 scripts/scap-delta.py reports/before.xml reports/after.xml

destroy: ## Tear down the VM
	vagrant destroy -f

# --- golden image path -------------------------------------------------------
#
# The VM path above measures remediation on a running host. This path bakes the
# controls into an image and gates the build on the score, so a control that
# stops working fails CI instead of shipping.
#
# Scoped to the container-applicable subset, 71 of 1532 rules. See
# findings/golden-image-gate.txt for why that number is what it is.

IMAGE   := rhel9-hardened-golden
OSCAP   := oscap xccdf eval --profile $(PROFILE)

image: ## Build the hardened golden image
	docker build -t $(IMAGE):latest -f image/Containerfile image/

image-scan: image ## Scan the built image -> reports/image.xml
	@mkdir -p reports
	docker run --rm --user root -v "$(CURDIR)/reports":/out $(IMAGE):latest 		bash -c "$(OSCAP) --results /out/image.xml $(SSG) >/dev/null 2>&1; true"

image-gate: image-scan ## Fail the build if the image regressed against the baseline
	python3 scripts/image-gate.py reports/image.xml --baseline image/baseline.json

image-baseline: image-scan ## Rewrite the committed baseline. Deliberate, and reviewable in a diff.
	python3 scripts/image-gate.py reports/image.xml --baseline image/baseline.json --update-baseline

image-control: ## Positive control: break a scored rule, prove the gate catches it
	bash scripts/image-positive-control.sh
