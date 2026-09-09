# Provider requirements. Auth is never configured here: the provider reads
# OS_CLOUD / clouds.yaml or OS_* environment variables, so no credential can
# end up in state-free files. This module targets any OpenStack cloud —
# chosen over a hyperscaler because OpenStack is what many European academic
# and public-sector clouds run.

terraform {
  required_version = ">= 1.5"

  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 3.4"
    }
  }

  # Remote state (recommended for any shared use) is documented in README.md
  # and deliberately not enabled by default: `terraform init` should work for
  # a reviewer without any infrastructure. See "Remote state" in the README.
}

provider "openstack" {
  # Intentionally empty: credentials come from the environment.
}
