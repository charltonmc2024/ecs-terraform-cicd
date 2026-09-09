resource "aws_eip" "eip" {
  domain = "vpc"
  tags = {

    Name = "${var.app_name}-${var.environment}-nat-eip"
  }

}
