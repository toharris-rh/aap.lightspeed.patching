output "linux_inventory" {
  description = "Linux VM inventory data for AAP host registration."
  value = {
    host           = aws_instance.rhel.public_dns
    ansible_host   = aws_instance.rhel.public_ip
    ansible_user   = var.linux_admin_username
    vm_name        = local.vm_name
    instance_id    = aws_instance.rhel.id
    vm_size_tier   = var.vm_size_tier
    vm_size_chosen = local.instance_type
  }
}
