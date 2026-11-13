# Сеть
resource "yandex_vpc_network" "main" {
  name = var.network_name
}

# Подсеть
resource "yandex_vpc_subnet" "main" {
  name           = "${var.network_name}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = [var.subnet_cidr]
}

# Security Group
resource "yandex_vpc_security_group" "main" {
  name        = var.sg_name
  description = "SG for ELK lab"
  network_id  = yandex_vpc_network.main.id

  ingress {
    protocol       = "ANY"
    description    = "Internal traffic"
    v4_cidr_blocks = [var.internal_cidr]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    protocol       = "TCP"
    description    = "SSH"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 22
    to_port        = 22
  }

  ingress {
    protocol       = "TCP"
    description    = "Elasticsearch HTTP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 9200
    to_port        = 9200
  }

  ingress {
    protocol       = "TCP"
    description    = "Kibana"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 5601
    to_port        = 5601
  }

  ingress {
    protocol       = "TCP"
    description    = "Logstash Beats"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 5044
    to_port        = 5044
  }

  ingress {
    protocol       = "TCP"
    description    = "Logstash TCP JSON"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 5000
    to_port        = 5000
  }

  ingress {
    protocol       = "TCP"
    description    = "Logstash API"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 9600
    to_port        = 9600
  }

  ingress {
    protocol       = "TCP"
    description    = "MyApp"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 8000
    to_port        = 8000
  }

  egress {
    protocol       = "ANY"
    description    = "All egress"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# VM (прерываемая)
resource "yandex_compute_instance" "elk" {
  name        = var.vm_name
  zone        = var.zone
  platform_id = var.platform_id

  resources {
    cores         = var.vm_cores
    memory        = var.vm_memory
    core_fraction = var.core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = var.vm_image_id
      size     = var.disk_size
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.main.id]
  }

  scheduling_policy {
    preemptible = true
  }

  metadata = {
    ssh-keys = "${var.ssh_user}:${file(var.ssh_public_key)}"
    user-data = templatefile("${path.module}/cloud-init.yaml", {
      hostname       = var.vm_name
      ssh_user       = var.ssh_user
      ssh_public_key = file(var.ssh_public_key)
      timezone       = var.timezone
      elk_version    = var.elk_version
    })
  }
}

# Ждём, пока cloud-init внутри VM завершит установку и запустит Kibana
resource "null_resource" "wait_for_kibana" {
  depends_on = [yandex_compute_instance.elk]

  triggers = {
    vm_id = yandex_compute_instance.elk.id
  }

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file("/home/Ollrins/key") 
    host        = yandex_compute_instance.elk.network_interface[0].nat_ip_address
    timeout     = "10m"
  }

  provisioner "remote-exec" {
    inline = [
      "echo 'Waiting for cloud-init to finish...'",
      "sudo cloud-init status --wait",
      "echo 'Waiting for Kibana to respond...'",
      "for i in $(seq 1 60); do if curl -s -o /dev/null -w '%%{http_code}' http://localhost:5601/api/status | grep -q '200'; then echo 'Kibana is ready'; exit 0; fi; echo \"Attempt $i/60 - Kibana not ready yet, sleeping 10s...\"; sleep 10; done",
      "echo 'Kibana did not become ready in time' && exit 1"
    ]
  }
}

output "vm_public_ip" {
  value       = yandex_compute_instance.elk.network_interface[0].nat_ip_address
  description = "Public IP"
}

output "kibana_url" {
  value       = "http://${yandex_compute_instance.elk.network_interface[0].nat_ip_address}:5601"
}

output "elasticsearch_url" {
  value       = "http://${yandex_compute_instance.elk.network_interface[0].nat_ip_address}:9200"
}

output "myapp_url" {
  value       = "http://${yandex_compute_instance.elk.network_interface[0].nat_ip_address}:8000"
}

output "ssh_command" {
  value       = "ssh ${var.ssh_user}@${yandex_compute_instance.elk.network_interface[0].nat_ip_address}"
}
