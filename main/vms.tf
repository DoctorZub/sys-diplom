
#считываем данные об образе ОС
data "yandex_compute_image" "ubuntu_2204_lts" {
  family = "ubuntu-2204-lts"
}

/// Bastion
resource "yandex_compute_instance" "bastion" {
  name        = "bastion" 
  hostname    = "bastion"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }
  
  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

  # scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a.id #зона ВМ должна совпадать с зоной subnet!!!
    nat                = true
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.bastion.id]
  }
}

/// Web-A
resource "yandex_compute_instance" "web_a" {
  name        = "web-a"
  hostname    = "web-a"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"


  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

  # scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.webs.id]
  }
}

/// Web-B
resource "yandex_compute_instance" "web_b" {
  name        = "web-b"
  hostname    = "web-b"
  platform_id = "standard-v3"
  zone        = "ru-central1-b"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

 # scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_b.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.webs.id]

  }
}

/// Zabbix_server
resource "yandex_compute_instance" "zabbix" {
  name        = "zabbix"
  hostname    = "zabbix"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

#  scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a_pub.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.zabbix-server.id]

  }
}


/// Elasticsearch
resource "yandex_compute_instance" "elastic" {
  name        = "elastic"
  hostname    = "elastic"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 4
    memory        = 8
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

 # scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.elastic.id]

  }
}


/// Logstash
resource "yandex_compute_instance" "logstash" {
  name        = "logstash"
  hostname    = "logstash"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 4
    memory        = 8
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

#  scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a.id
    nat                = false
    security_group_ids = [yandex_vpc_security_group.LAN.id]

  }
}


/// Kibana
resource "yandex_compute_instance" "kibana" {
  name        = "kibana"
  hostname    = "kibana"
  platform_id = "standard-v3"
  zone        = "ru-central1-a"

  resources {
    cores         = 2
    memory        = 4
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu_2204_lts.image_id
      type     = "network-hdd"
      size     = 10
    }
  }

  lifecycle{
    ignore_changes = [boot_disk.0.initialize_params.0.image_id]
  }

  metadata = {
    user-data          = file("./cloud-init.yml")
    serial-port-enable = 1
  }

#  scheduling_policy { preemptible = true }

  network_interface {
    subnet_id          = yandex_vpc_subnet.develop_a_pub.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.LAN.id, yandex_vpc_security_group.kibana.id]

  }
}

/// Inventory for Ansible
resource "local_file" "inventory" {
  content  = <<-XYZ
  [bastion]
  ${yandex_compute_instance.bastion.hostname}.ru-central1.internal

  [webservers]
  ${yandex_compute_instance.web_a.hostname}.ru-central1.internal
  ${yandex_compute_instance.web_b.hostname}.ru-central1.internal
  
  [zabbix]
  ${yandex_compute_instance.zabbix.hostname}.ru-central1.internal

  [elasticsearch]
  ${yandex_compute_instance.elastic.hostname}.ru-central1.internal

  [logstash]
  ${yandex_compute_instance.logstash.hostname}.ru-central1.internal

  [kibana]
  ${yandex_compute_instance.kibana.hostname}.ru-central1.internal
  XYZ
  filename = "./ansible/inventory.yml"
}
