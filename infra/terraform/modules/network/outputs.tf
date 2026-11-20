output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_id" {
  value      = aws_subnet.public.id
  depends_on = [aws_internet_gateway.this, aws_route_table_association.public]
}
