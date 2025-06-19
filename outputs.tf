output "bastion_alias" {
  description = "Bastion SSH alias."
  value       = "alias ${var.bastion_name}=ssh ${var.bastion_admin_user_name}@${cloudflare_dns_record.bastion_dns.name} -t -- "
  depends_on  = [cloudflare_dns_record.bastion_dns]
}
