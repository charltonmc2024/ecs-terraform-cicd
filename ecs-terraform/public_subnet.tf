resource "aws_subnet" "public1" {

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr1
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-subnet-1"
  }

}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr2
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public_subnet-2"
  }

}

resource "aws_route_table_association" "public_1" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public1.id

}

resource "aws_route_table_association" "public_2" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id      = aws_subnet.public2.id
}