/// Target Group
resource "yandex_alb_target_group" "tg-alb" {
  name = "tg-alb"

  target {
    subnet_id  = yandex_vpc_subnet.develop_a.id
    ip_address = yandex_compute_instance.web_a.network_interface.0.ip_address
  }

  target {
    subnet_id  = yandex_vpc_subnet.develop_b.id
    ip_address = yandex_compute_instance.web_b.network_interface.0.ip_address
  }
}

/// Backend
resource "yandex_alb_backend_group" "backend1" {
  name = "backend1"

  http_backend {
    name             = "backend1"
    port             = 80
    target_group_ids = ["${yandex_alb_target_group.tg-alb.id}"]
    healthcheck {
      timeout  = "2s"
      interval = "2s"
      healthcheck_port = 80
      healthy_threshold = 0
      http_healthcheck {
        path = "/"
      }
    }
  }
}


/// HTTP-router
resource "yandex_alb_http_router" "http-router1" {
  name = "http-router1"
}


/// Virtual Host
resource "yandex_alb_virtual_host" "vh1" {
  name           = "vh1"
  http_router_id = yandex_alb_http_router.http-router1.id
  route {
    name = "to-backend1"
    http_route {
      http_route_action {
        backend_group_id = yandex_alb_backend_group.backend1.id
        timeout          = "3s"
      }
    }
  }
}


/// ALB
resource "yandex_alb_load_balancer" "alb1" {
  name = "alb1"

  network_id = yandex_vpc_network.develop.id

  allocation_policy {
    location {
      zone_id   = "ru-central1-a"
      subnet_id = yandex_vpc_subnet.develop_a_pub.id
    }
  }

  listener {
    name = "my-listener"
    endpoint {
      address {
        external_ipv4_address {
        }
      }
      ports = [80]
    }
    http {
      handler {
        http_router_id = yandex_alb_http_router.http-router1.id
      }
    }
  }

  log_options {
    disable = "true"
  }
}
