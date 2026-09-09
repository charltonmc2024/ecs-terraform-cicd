resource "aws_ecr_repository" "ecr_repo" {

  name                 = "${var.app_name}-${var.environment}-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    Name = "${var.app_name}-${var.environment}-repo"

  }

}
