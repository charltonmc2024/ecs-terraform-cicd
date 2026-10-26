# Optional S3 Gateway endpoint.
# The Gateway endpoint lets private subnets reach S3 over the AWS network without a
# NAT Gateway, keeping that traffic off the public internet and avoiding per-GB NAT
# data-processing cost (used by ECR image-layer pulls, which are backed by S3, and
# by frontend asset access). It is gated on enable_vpc_endpoints and off by default
# in dev, so when disabled zero endpoint resources exist (count = 0). Both route
# tables are associated so the endpoint route is present regardless of which subnet
# tier originates the request.
#
# No DynamoDB Gateway endpoint is created: the application database is MongoDB Atlas
# (an external managed service reached over the internet via the NAT Gateway), not
# DynamoDB, so a DynamoDB endpoint would serve no traffic.
resource "aws_vpc_endpoint" "s3" {
  count = var.enable_vpc_endpoints ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public_route_table.id, aws_route_table.private_route_table.id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-s3-endpoint"
  })
}
