module "service_provider_account_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.4"

  name = "${local.app_name}-vpc"
  cidr = local.service_provider_vpc_cidr

  azs             = ["${local.aws_region}a", "${local.aws_region}b"]
  public_subnets  = local.service_provider_vpc_public_subnets
  private_subnets = local.service_provider_vpc_private_subnets

  enable_nat_gateway     = true
  single_nat_gateway     = true
  one_nat_gateway_per_az = false

  enable_dns_hostnames = true
  enable_dns_support   = true


  tags = {
    Name = "${local.service_provider_app_name}-vpc"
  }

  private_subnet_tags = {
    Name = "private-subnet"
  }

  public_subnet_tags = {
    Name = "public-subnet"
  }
}
