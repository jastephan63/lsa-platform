# Security groups mirror the NetworkPolicy story inside the cluster (see
# docs/network.md): the perimeter is enforced at the cloud layer, east-west
# is restricted by referencing groups instead of CIDRs — "the database
# accepts 5432 from members of the app group", wherever those instances are.

resource "openstack_networking_secgroup_v2" "web" {
  name        = "${var.name_prefix}-web"
  description = "App instance: HTTP(S) from anywhere, SSH from the admin network only"
}

resource "openstack_networking_secgroup_rule_v2" "web_http" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 80
  port_range_max    = 80
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "web_https" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_rule_v2" "web_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = var.allowed_ssh_cidr
  security_group_id = openstack_networking_secgroup_v2.web.id
}

resource "openstack_networking_secgroup_v2" "db" {
  name        = "${var.name_prefix}-db"
  description = "Database instance: PostgreSQL from the web group only, no SSH from outside"
}

resource "openstack_networking_secgroup_rule_v2" "db_postgres_from_web" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 5432
  port_range_max    = 5432
  remote_group_id   = openstack_networking_secgroup_v2.web.id
  security_group_id = openstack_networking_secgroup_v2.db.id
}

resource "openstack_networking_secgroup_rule_v2" "db_ssh_from_web" {
  # Admin path to the DB host is a hop over the app instance (bastion style),
  # never a direct exposure.
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.web.id
  security_group_id = openstack_networking_secgroup_v2.db.id
}
