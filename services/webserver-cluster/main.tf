locals {
  http_port = 80
  any_port = 0
  any_protocol = "-1"
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

resource "aws_security_group" "web_server_secu" {
  name = "${var.cluster_name}-web_server_secu"

  ingress {
    from_port = var.server_port
    to_port = var.server_port
    protocol = local.tcp_protocol
    cidr_blocks = local.all_ips
  }
}

resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

  cidr_blocks = local.all_ips
  protocol = local.tcp_protocol
  from_port = local.http_port
  to_port = local.http_port
}

resource "aws_security_group_rule" "allow_all_outbound" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

  cidr_blocks = local.all_ips
  protocol = local.any_protocol
  from_port = local.any_port
  to_port = local.any_port
}

resource "aws_launch_configuration" "webLaunchConfig" {
  image_id = "ami-0e67aff698cb24c1d"
  instance_type = var.instance_type
  security_groups = [ aws_security_group.web_server_secu.id ]

  user_data = data.template_file.user_data.rendered

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "auto_scaling_web" {
  launch_configuration = aws_launch_configuration.webLaunchConfig.name
  vpc_zone_identifier = data.aws_subnet_ids.web_subnet.ids
  target_group_arns = [ aws_lb_target_group.web.arn ]
  health_check_type = "ELB"

  min_size = var.min_size
  max_size = var.max_size

  tag {
    key = "Name"
    value = var.cluster_name
    propagate_at_launch = true
  }
}

resource "aws_lb" "lb_web" {
  name = "terraform-asg-example"
  load_balancer_type = "application"
  subnets = data.aws_subnet_ids.web_subnet.ids
  security_groups = [ aws_security_group.alb.id ]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lb_web.arn
  port = local.http_port
  protocol = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code = 404
    }
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
  
}

resource "aws_lb_target_group" "web" {
  name = "terraform-asg-example"
  port = var.server_port
  protocol = "HTTP"
  vpc_id = data.aws_vpc.web.id

  health_check {
    path = "/"
    protocol = "HTTP"
    matcher = "200"
    interval = 15
    timeout = 3
    healthy_threshold = 2
    unhealthy_threshold = 2
  }
}

data "aws_vpc" "web" {
  default = true
}

data "aws_subnet_ids" "web_subnet" {
  vpc_id = data.aws_vpc.web.id
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state.key
    region = "ap-northeast-2"
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/user_data.sh")

  vars = {
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port = data.terraform_remote_state.db.outputs.port
  }
}