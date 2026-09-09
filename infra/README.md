# infra — OpenStack module

Terraform module for the cloud layer under the Kubernetes cluster: private
network, subnet, router to the provider's external network, security groups,
an operator keypair, two instances (app, database), and one floating IP on
the app instance only. It targets the OpenStack provider — the stack many
European academic and public-sector clouds run — rather than a hyperscaler.

> **Honest scope:** this module is `terraform fmt`/`validate`/tflint-clean in
> CI and reviewed by hand. It has **never been applied against a real
> OpenStack project**; applying it needs credentials (`OS_CLOUD` /
> `clouds.yaml`) and provider-specific names for the external network, image,
> and flavors.

## Usage

```hcl
module "lsa" {
  source           = "./infra"
  public_key       = file("~/.ssh/id_ed25519.pub")
  allowed_ssh_cidr = "203.0.113.0/24" # your admin network, never 0.0.0.0/0
}
```

Plan without credentials (what CI does):

```bash
terraform -chdir=infra init -backend=false
terraform -chdir=infra validate
```

## Remote state

For any shared use, configure a remote backend so state (which contains
resource IDs and IP addresses) is not a local file. On an OpenStack cloud the
natural choice is the S3-compatible object store:

```hcl
terraform {
  backend "s3" {
    bucket   = "lsa-terraform-state"
    key      = "lsa-platform.tfstate"
    endpoint = "https://objects.example-openstack.org" # your provider's object-store endpoint
    # credentials via AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (EC2-style keys)
    skip_credentials_validation = true
    skip_region_validation      = true
  }
}
```

Not enabled by default so that `terraform init` works for a reviewer with no
infrastructure at all.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_openstack"></a> [openstack](#requirement\_openstack) | ~> 3.4 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_openstack"></a> [openstack](#provider\_openstack) | 3.4.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [openstack_compute_instance_v2.app](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2) | resource |
| [openstack_compute_instance_v2.db](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_instance_v2) | resource |
| [openstack_compute_keypair_v2.operator](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/compute_keypair_v2) | resource |
| [openstack_networking_floatingip_associate_v2.app](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_associate_v2) | resource |
| [openstack_networking_floatingip_v2.app](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_floatingip_v2) | resource |
| [openstack_networking_network_v2.net](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_network_v2) | resource |
| [openstack_networking_port_v2.app](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_port_v2) | resource |
| [openstack_networking_port_v2.db](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_port_v2) | resource |
| [openstack_networking_router_interface_v2.router_if](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_interface_v2) | resource |
| [openstack_networking_router_v2.router](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_router_v2) | resource |
| [openstack_networking_secgroup_rule_v2.db_postgres_from_web](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_rule_v2.db_ssh_from_web](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_rule_v2.web_http](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_rule_v2.web_https](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_rule_v2.web_ssh](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_rule_v2) | resource |
| [openstack_networking_secgroup_v2.db](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2) | resource |
| [openstack_networking_secgroup_v2.web](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_secgroup_v2) | resource |
| [openstack_networking_subnet_v2.subnet](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/resources/networking_subnet_v2) | resource |
| [openstack_compute_flavor_v2.app](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/compute_flavor_v2) | data source |
| [openstack_compute_flavor_v2.db](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/compute_flavor_v2) | data source |
| [openstack_images_image_v2.os](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/images_image_v2) | data source |
| [openstack_networking_network_v2.external](https://registry.terraform.io/providers/terraform-provider-openstack/openstack/latest/docs/data-sources/networking_network_v2) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allowed_ssh_cidr"></a> [allowed\_ssh\_cidr](#input\_allowed\_ssh\_cidr) | CIDR allowed to reach SSH on the app instance. Default deliberately requires an explicit decision instead of 0.0.0.0/0. | `string` | n/a | yes |
| <a name="input_db_flavor_name"></a> [db\_flavor\_name](#input\_db\_flavor\_name) | Compute flavor for the database instance. | `string` | `"m1.small"` | no |
| <a name="input_dns_nameservers"></a> [dns\_nameservers](#input\_dns\_nameservers) | DNS resolvers handed out on the subnet. | `list(string)` | <pre>[<br/>  "9.9.9.9",<br/>  "149.112.112.112"<br/>]</pre> | no |
| <a name="input_external_network_name"></a> [external\_network\_name](#input\_external\_network\_name) | Name of the provider's external (public) network. On many OpenStack clouds this is simply 'public'. | `string` | `"public"` | no |
| <a name="input_flavor_name"></a> [flavor\_name](#input\_flavor\_name) | Compute flavor for the application instance. | `string` | `"m1.small"` | no |
| <a name="input_image_name"></a> [image\_name](#input\_image\_name) | Glance image for the instances (an Ubuntu LTS image name as published by the cloud). | `string` | `"Ubuntu 24.04 LTS"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for every resource name, so multiple deployments can share a project. | `string` | `"lsa"` | no |
| <a name="input_public_key"></a> [public\_key](#input\_public\_key) | SSH public key material for the operator keypair. Only the public half — the private key never touches Terraform. | `string` | n/a | yes |
| <a name="input_subnet_cidr"></a> [subnet\_cidr](#input\_subnet\_cidr) | CIDR of the private subnet the instances live in. | `string` | `"10.10.10.0/24"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_floating_ip"></a> [app\_floating\_ip](#output\_app\_floating\_ip) | Public IP of the application instance. |
| <a name="output_app_private_ip"></a> [app\_private\_ip](#output\_app\_private\_ip) | Private address of the application instance. |
| <a name="output_db_private_ip"></a> [db\_private\_ip](#output\_db\_private\_ip) | Private address of the database instance (no public IP by design). |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | ID of the private network. |
| <a name="output_web_security_group_id"></a> [web\_security\_group\_id](#output\_web\_security\_group\_id) | Security group protecting the app instance. |
<!-- END_TF_DOCS -->
