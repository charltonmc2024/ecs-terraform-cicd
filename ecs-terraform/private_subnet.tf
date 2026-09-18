resource "aws_subnet" "private1" {
  vpc_id = aws_vpc.main.id

  cidr_block = var.private_subnet_cidr1

  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${local.name_prefix}-private-subnet-1"
  }
}

resource "aws_subnet" "private2" {
  vpc_id = aws_vpc.main.id

  cidr_block = var.private_subnet_cidr2

  availability_zone = "${var.aws_region}b"

  tags = {
    Name = "${local.name_prefix}-private-subnet-2"
  }

}
resource "aws_route_table_association" "private_1" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private1.id
}

resource "aws_route_table_association" "private_2" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id      = aws_subnet.private2.id
}
