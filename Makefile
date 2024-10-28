.PHONY: tf-init tf-fmt tf-validate tf-plan tf-apply tf-destroy

tf-init:
	terraform init

tf-fmt:
	terraform fmt

tf-validate:
	terraform validate

tf-plan:
	terraform plan

tf-apply:
	terraform apply --auto-approve

tf-destroy:
	terraform destroy --auto-approve
