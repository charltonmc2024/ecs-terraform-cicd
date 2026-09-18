resource "aws_ecr_repository" "ecr_repo" {

  name                 = "${local.name_prefix}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "${local.name_prefix}-repo"

  }

}
