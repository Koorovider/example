locals {
  vpc = {
    "sdxx365-vpc" = {
      cidr  = "10.21.0.0/16"
      enable_nat_gateway = true
      azs   = ["ap-northeast-2a", "ap-northeast-2b"]

      private = {
        subnets = ["10.21.0.0/24", "10.21.1.0/24"]
        tags    = {
          "kubernetes.io/role/internal-elb" = 1
        }
      }

      public = {
        subnets = ["10.21.32.0/24", "10.21.33.0/24"]
        tags    = {
          "kubernetes.io/role/elb" = 1
        }
      }
      tags = {
	      terraform-aws-modules = "vpc"
      }
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  for_each = local.vpc

  name = each.key
  cidr = each.value.cidr

  azs             = try(each.value.azs, [])
  private_subnets = try(each.value.private.subnets, [])
  public_subnets  = try(each.value.public.subnets, [])

  enable_nat_gateway = try(each.value.enable_nat_gateway, false)

  private_subnet_tags = try(each.value.private.tags, {})
  public_subnet_tags  = try(each.value.public.tags, {})

  tags = try(each.value.tags, {})
}

