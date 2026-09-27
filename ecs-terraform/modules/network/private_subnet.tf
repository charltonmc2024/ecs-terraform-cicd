# Two private subnets, one per availability zone. ECS Fargate tasks run here with
# map_public_ip_on_launch = false so they never receive a public IP and stay off the
# public internet. Egress (when needed) is provided via the optional NAT Gateway.
# AZs come from the aws_availability_zones data source so the module is portable
# across regions rather than assuming "<region>a"/"<region>b".
resource "aws_subnet" "private1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr1
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-subnet-1"
  })
}

resource "aws_subnet" "private2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-subnet-2"
  })
}

# Associate both private subnets with the shared private route table declared in
# private_route_table.tf. This file owns the private associations (the route table
# file intentionally declares none).
resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private1.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private2.id
  route_table_id = aws_route_table.private_route_table.id
}
