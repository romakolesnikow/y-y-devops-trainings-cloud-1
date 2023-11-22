terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">= 0.13"
}

provider "yandex" {
  service_account_key_file = "./tf_key.json"
  folder_id                = local.folder_id
  zone                     = "ru-central1-a"
}

resource "yandex_vpc_network" "foo" {
  folder_id = "b1g36oe50ssd59n9jrug"
  name           = "catgpt-network"
}

resource "yandex_vpc_subnet" "foo" {
  folder_id = "b1g36oe50ssd59n9jrug"
  name           = "catgpt-subnet"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.foo.id
  v4_cidr_blocks = ["10.20.30.0/24"]
  route_table_id = yandex_vpc_route_table.rt.id
}

resource "yandex_vpc_gateway" "nat_gateway" {
  name = "test-gateway"
  shared_egress_gateway {}
}
resource "yandex_vpc_route_table" "rt" {
  name       = "test-route-table"
  network_id = yandex_vpc_network.foo.id
  static_route {
    destination_prefix = "0.0.0.0/0"
    gateway_id         = yandex_vpc_gateway.nat_gateway.id
  }
}
locals {
  folder_id = "b1g36oe50ssd59n9jrug"
  service-accounts = toset([
    "catgpt-service-acc",
  ])
  catgpt-sa-roles = toset([
    "container-registry.images.puller",
    "monitoring.editor", "compute.admin", "load-balancer.privateAdmin", "vpc.admin"
  ])
}

resource "yandex_iam_service_account" "service-accounts" {
  for_each = local.service-accounts
  name     = each.key
}

resource "yandex_resourcemanager_folder_iam_member" "catgpt-roles" {
  for_each  = local.catgpt-sa-roles
  folder_id = local.folder_id
  member    = "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-service-acc"].id}"
  role      = each.key
  depends_on = [
    yandex_iam_service_account.service-accounts["catgpt-service-acc"],
  ]
}

data "yandex_compute_image" "coi" {
  family = "container-optimized-image"
}

resource "yandex_resourcemanager_folder_iam_binding" "editor" {
  folder_id = local.folder_id
  role      = "editor"
  members = [
    "serviceAccount:${yandex_iam_service_account.service-accounts["catgpt-service-acc"].id}",
  ]
  depends_on = [
    yandex_iam_service_account.service-accounts,
  ]
}
# resource "yandex_compute_instance" "catgpt-1" {
#     platform_id        = "standard-v2"
#     service_account_id = yandex_iam_service_account.service-accounts["catgpt-service-acc"].id
#     resources {
#       cores         = 2
#       memory        = 1
#       core_fraction = 5
#     }
#     scheduling_policy {
#       preemptible = true
#     }
#     network_interface {
#       subnet_id = "${yandex_vpc_subnet.foo.id}"
#       nat = true
#     }
#     boot_disk {
#       initialize_params {
#         type = "network-hdd"
#         size = "30"
#         image_id = data.yandex_compute_image.coi.id
#       }
#     }
#     metadata = {
#       docker-compose = file("${path.module}/docker-compose.yaml")
#       ssh-keys  = "ubuntu:${file("~/.ssh/devops_training.pub")}"
#     }
# }

resource "yandex_compute_instance_group" "ig-catgpt" {
  service_account_id = yandex_iam_service_account.service-accounts["catgpt-service-acc"].id
  name = "ig-catgpt"
  folder_id = local.folder_id
  
  instance_template {
    platform_id = "standard-v2"
    resources {
      cores         = 2
      memory        = 1
      core_fraction = 5
    }
    scheduling_policy {
      preemptible = true
    }
    boot_disk {
      initialize_params {
        type = "network-hdd"
        size = "30"
        image_id = data.yandex_compute_image.coi.id
      }
    }
    network_interface {
      network_id = yandex_vpc_network.foo.id
      subnet_ids = ["${yandex_vpc_subnet.foo.id}"]
      #nat = true
    }
    metadata = {
      docker-compose = file("${path.module}/docker-compose.yaml")
      ssh-keys  = "poma:${file("~/.ssh/id_ed25519.pub")}"
#      docker-config = file("${/home/poma/.docker/config.json}}")
    }
  }
  scale_policy {
    fixed_scale {
      size = 2
    }
  }
  allocation_policy {
    zones = ["ru-central1-a"]
  }
  deploy_policy {
    max_unavailable = 1
    max_creating    = 1
    max_expansion   = 1
    max_deleting    = 1
  }
  load_balancer {
    target_group_name        = "target-group"
    target_group_description = "load balancer target group"
  }
}

# resource "yandex_lb_target_group" "foo" {
#   name        = "lbtargetgroup"
#   target {
#     subnet_id = "${yandex_vpc_subnet.foo.id}"
#     address   = "${yandex_compute_instance_group.ig-catgpt.instances[0].network_interface[0].ip_address}"
#   }
#     target {
#     subnet_id = "${yandex_vpc_subnet.foo.id}"
#     address   = "${yandex_compute_instance_group.ig-catgpt.instances[1].network_interface[1].ip_address}"
#   }
# }

resource "yandex_lb_network_load_balancer" "foo" {
  name = "networkloadbalancer"
  attached_target_group {
    target_group_id = yandex_compute_instance_group.ig-catgpt.load_balancer[0].target_group_id
    healthcheck {
      name = "health"
      http_options {
        port = 8080
        path = "/ping"
      }
    }
  }
  listener {
    name        = "test-listener"
    port        = 8080
    target_port = 80
    protocol    = "tcp"
    external_address_spec {
      ip_version = "ipv4"
    }
  }
    listener {
    name        = "ssh-listener"
    port        = 22
    target_port = 22
    protocol    = "tcp"
    external_address_spec {
      ip_version = "ipv4"
    }
  }
}
# resource "yandex_alb_http_router" "tf-router" {
#   name      = "my-http-router"
# }

# resource "yandex_alb_backend_group" "test-backend-group" {
# #  name      = "target-group"

#   http_backend {
#     name = "test-http-backend"
#     weight = 1
#     port = 8080
#     target_group_ids = [yandex_compute_instance_group.ig-catgpt.application_load_balancer[0].target_group_id]
 
#     healthcheck {
#       timeout             = "10s"
#       interval            = "2s"
#       healthy_threshold   = 10
#       unhealthy_threshold = 15
#       http_healthcheck {
#         path  = "/ping"
#       }
#     }
#   }
# }

# resource "yandex_alb_load_balancer" "l7catgptalb" {
#   name        = "l7catgptalb"
#   network_id  = yandex_vpc_network.foo.id
# #  security_group_ids = ["<идентификатор_группы_безопасности>"]

#   allocation_policy {
#     location {
#       zone_id   = "ru-central1-a"
#       subnet_id = "${yandex_vpc_subnet.foo.id}"
#     }
#   }

#   listener {
#     name = "listener"
#     endpoint {
#       address {
#         external_ipv4_address {
#         }
#       }
#       ports = [ 80 ]
#     }
#     http {
#       handler {
#         http_router_id = "${yandex_alb_http_router.tf-router.id}"
#       }
#     }
#   }
# }

# resource "yandex_alb_virtual_host" "catgptvhost" {
#   name           = "catgptvhost"
#   http_router_id = "${yandex_alb_http_router.tf-router.id}"
#   route {
#     name = "catgptroute"
#     http_route {
#       http_route_action {
#         backend_group_id = yandex_alb_backend_group.test-backend-group.id
#         timeout          = "60s"
#       }
#     }
#   }
# }
