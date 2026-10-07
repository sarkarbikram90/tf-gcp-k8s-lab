output "allow_internal_rule_name" {
  description = "Name of the baseline internal subnet firewall rule (null in strict mode)"
  value       = try(google_compute_firewall.allow_internal[0].name, null)
}

output "allow_iap_ssh_rule_name" {
  description = "Name of the IAP SSH firewall rule"
  value       = google_compute_firewall.allow_iap_ssh.name
}

output "allow_health_checks_rule_name" {
  description = "Name of the health checks firewall rule"
  value       = try(google_compute_firewall.allow_health_checks[0].name, try(google_compute_firewall.strict_apiserver[0].name, null))
}

output "strict_rules" {
  description = "Names of strict firewall rules if strict_mode is enabled"
  value = var.strict_mode ? {
    etcd      = google_compute_firewall.strict_etcd[0].name
    apiserver = google_compute_firewall.strict_apiserver[0].name
    kubelet   = google_compute_firewall.strict_kubelet[0].name
    cni       = google_compute_firewall.strict_cni_overlay[0].name
    coredns   = google_compute_firewall.strict_coredns[0].name
    nodeports = google_compute_firewall.strict_nodeports[0].name
  } : {}
}
