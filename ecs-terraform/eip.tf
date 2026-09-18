resource "aws_eip" "eip" {
  domain = "vpc"
  tags = {

    Name = "${local.name_prefix}-nat-eip"
  }

}
