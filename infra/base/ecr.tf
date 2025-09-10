resource "aws_ecr_repository" "quotes" {
  name         = "${var.prefix}-quotes"
  force_delete = false

  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "newsfeed" {
  name         = "${var.prefix}-newsfeed"
  force_delete = false

  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "front_end" {
  name         = "${var.prefix}-front_end"
  force_delete = false

  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
}

data "aws_caller_identity" "current" {}

locals {
  ecr_url = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.prefix}-"
}

resource "aws_ssm_parameter" "ecr" {
  name = "/${var.prefix}/base/ecr"
  value = local.ecr_url
  type  = "String"
}

resource "local_file" "ecr" {
  filename = "${path.module}/../ecr-url.txt"
  content = local.ecr_url
}

output "repository_base_url" {
  value = local.ecr_url
}
