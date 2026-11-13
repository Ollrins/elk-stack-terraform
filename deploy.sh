#!/bin/bash
set -e
cd ~/elk-lab/terraform
terraform apply -target=yandex_compute_instance.elk -auto-approve
IP=$(terraform output -raw vm_public_ip)
sed -i "s/kibana_ip *= *\".*\"/kibana_ip = \"$IP\"/" terraform.tfvars
terraform apply -auto-approve
