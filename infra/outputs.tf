output "app_floating_ip" {
  description = "Public IP of the application instance."
  value       = openstack_networking_floatingip_v2.app.address
}

output "app_private_ip" {
  description = "Private address of the application instance."
  value       = openstack_networking_port_v2.app.all_fixed_ips[0]
}

output "db_private_ip" {
  description = "Private address of the database instance (no public IP by design)."
  value       = openstack_networking_port_v2.db.all_fixed_ips[0]
}

output "network_id" {
  description = "ID of the private network."
  value       = openstack_networking_network_v2.net.id
}

output "web_security_group_id" {
  description = "Security group protecting the app instance."
  value       = openstack_networking_secgroup_v2.web.id
}
