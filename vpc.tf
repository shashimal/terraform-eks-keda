module "service_provider_account_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.4"

  name = "${local.app_name}-vpc"
  cidr = local.cidr

  azs             = ["${data.aws_region.current.region}a", "${data.aws_region.current.region}b"]
  public_subnets  = local.public_subnets
  private_subnets = local.private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true


  tags = {
    Name = "${local.app_name}-vpc"
  }

  private_subnet_tags = {
    Name = "private-subnet"
  }

  public_subnet_tags = {
    Name = "public-subnet"
  }
}
