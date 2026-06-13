locals {
  instance_type_map = {
    "small"  = "t3.medium"
    "medium" = "t3.large"
    "large"  = "t3.xlarge"
  }

  instance_type = local.instance_type_map[var.vm_size_tier]
  name_suffix   = random_string.suffix.result
  vm_name       = "lsp-rhel-${var.vm_size_tier}-${local.name_suffix}"

  common_tags = merge(var.tags, {
    Tier         = var.vm_size_tier
    InstanceType = local.instance_type
  })
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
  numeric = true
}
