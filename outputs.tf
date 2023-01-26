output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "db_fqdn" {
  value = module.delphix_db.fqdn
}
