resource "aws_launch_template" "ecs_launch_template" {
  name                   = "metabase-${var.environment}-asg-launch-template"
  image_id               = data.aws_ami.amazon_linux_2.id
  vpc_security_group_ids = [aws_security_group.metabase_ecs_sg.id]
  user_data              = base64encode("#!/bin/bash\necho ECS_CLUSTER=${aws_ecs_cluster.cluster.name} >> /etc/ecs/ecs.config")
  instance_type          = var.instance_type

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_role_profile.name
  }

  metadata_options {
    http_tokens   = "required"   # Enforces IMDSv2
    http_endpoint = "enabled"
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(
      {
        Name = "metabase-${var.environment}-instance"
      },
      var.default_tags,
      var.tags,
    )
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                      = "metabase-${var.environment}-autoscaling-group"
  vpc_zone_identifier       = var.private_subnet_ids
  min_size                  = 1
  max_size                  = var.desired_capacity
  desired_capacity          = var.desired_capacity
  health_check_grace_period = 300
  health_check_type         = "ELB"

  launch_template {
    id      = aws_launch_template.ecs_launch_template.id
    version = aws_launch_template.ecs_launch_template.latest_version
  }

  instance_refresh {
    strategy = "Rolling"

    preferences {
      instance_warmup        = 300          # seconds to wait after launch before health checks
      min_healthy_percentage = 90           # keep at least 90% healthy during refresh
      # max_healthy_percentage   = 110      # optional
      # skip_matching            = false    # optional: replace even if config matches
    }

    # Crucial: this triggers refresh automatically on launch template change
    # triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "metabase-${var.environment}-instance"
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = merge(var.default_tags, var.tags)

    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}
