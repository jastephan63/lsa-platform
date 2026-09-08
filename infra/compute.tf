data "openstack_images_image_v2" "os" {
  name        = var.image_name
  most_recent = true
}

data "openstack_compute_flavor_v2" "app" {
  name = var.flavor_name
}

data "openstack_compute_flavor_v2" "db" {
  name = var.db_flavor_name
}

resource "openstack_compute_keypair_v2" "operator" {
  name       = "${var.name_prefix}-operator"
  public_key = var.public_key
}

# Explicit ports: security groups attach to the port, and the floating IP
# association references the port — the modern (non-deprecated) shape.
resource "openstack_networking_port_v2" "app" {
  name               = "${var.name_prefix}-app-port"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.web.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
}

resource "openstack_networking_port_v2" "db" {
  name               = "${var.name_prefix}-db-port"
  network_id         = openstack_networking_network_v2.net.id
  security_group_ids = [openstack_networking_secgroup_v2.db.id]

  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.subnet.id
  }
}

resource "openstack_compute_instance_v2" "app" {
  name      = "${var.name_prefix}-app"
  image_id  = data.openstack_images_image_v2.os.id
  flavor_id = data.openstack_compute_flavor_v2.app.id
  key_pair  = openstack_compute_keypair_v2.operator.name

  network {
    port = openstack_networking_port_v2.app.id
  }
}

resource "openstack_compute_instance_v2" "db" {
  name      = "${var.name_prefix}-db"
  image_id  = data.openstack_images_image_v2.os.id
  flavor_id = data.openstack_compute_flavor_v2.db.id
  key_pair  = openstack_compute_keypair_v2.operator.name

  network {
    port = openstack_networking_port_v2.db.id
  }
}

# Only the app instance is reachable from outside; the database keeps a
# private address behind the router.
resource "openstack_networking_floatingip_v2" "app" {
  pool = var.external_network_name
}

resource "openstack_networking_floatingip_associate_v2" "app" {
  floating_ip = openstack_networking_floatingip_v2.app.address
  port_id     = openstack_networking_port_v2.app.id

  depends_on = [openstack_networking_router_interface_v2.router_if]
}
