resource "aws_route_table" "private_route_table" {

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.natgw.id
  }

  tags = {
    Name = "${var.app_name}-${var.environment}-private-route-table"
  }
}


