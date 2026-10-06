output "allow_internal_rule_name" {
  description = "Name of the internal subnet firewall rule"
  value       = google_compute_firewall.allow_internal.name
}

output "allow_iap_ssh_rule_name" {
  description = "Name of the IAP SSH firewall rule"
  value       = google_compute_firewall.allow_iap_ssh.name
}

output "allow_health_checks_rule_name" {
  description = "Name of the health checks firewall rule"
  value       = google_compute_firewall.allow_health_checks.name
}
