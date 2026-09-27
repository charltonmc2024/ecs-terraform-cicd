# Two public subnets spread across two availability zones for redundant
# placement of internet-facing resources such as the NAT Gateway.
# map_public_ip_on_launch is true so resources launched here receive a public IP.
# Route table associations to the IGW-routed public route table live in
# public_route_table.tf to keep association ownership in a single place.
# AZs come from the aws_availability_zones data source so the module is portable
# across regions rather than assuming "<region>a"/"<region>b".
resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr1
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-subnet-1"
  })
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr2
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-subnet-2"
  })
}
