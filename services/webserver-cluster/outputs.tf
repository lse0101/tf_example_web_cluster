output "alb_dns_name" {
  value = aws_lb.lb_web.dns_name
}

output "asg_name" {
  value = aws_autoscaling_group.auto_scaling_web.name
}

output "alb_security_group_id" {
  value = aws_security_group.alb.id
}