.PHONY: help up scan-before harden scan-after delta destroy
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
