resource "yandex_compute_snapshot_schedule" "ss1" {
  name = "ss1"

  schedule_policy {
    expression = "0 22 ? * *"
  }

  snapshot_count = 7

  disk_ids = [yandex_compute_instance.bastion.boot_disk.0.disk_id, yandex_compute_instance.web_a.boot_disk.0.disk_id, yandex_compute_instance.web_b.boot_disk.0.disk_id, yandex_compute_instance.zabbix.boot_disk.0.disk_id, yandex_compute_instance.elastic.boot_disk.0.disk_id, yandex_compute_instance.logstash.boot_disk.0.disk_id, yandex_compute_instance.kibana.boot_disk.0.disk_id]
}
