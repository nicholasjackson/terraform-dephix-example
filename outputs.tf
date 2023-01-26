output "alb_dns" {
  value = aws_lb.main.dns_name
}

output "db_fdqn" {
  value = module.delphix_db.fdqn
}
