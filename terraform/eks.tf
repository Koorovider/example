locals {
    eks = {
      sdxx365-eks = {
        cluster_version      = "1.32" # 최신 버전
        public_access        = true
        public_access_cidrs  = [ "" ] # 관리자 작업 위치
        vpc                  = module.vpc["sdxx365-vpc"].vpc_id
        subnet_ids           = module.vpc["sdxx365-vpc"].private_subnets
   
        eks_managed_node_groups = {
          test-group = {
            subnet_ids    = module.vpc["sdxx365-vpc"].private_subnets
            min_size     = 2
            max_size     = 2
            desired_size = 2
            block_device_mappings = {
              xvda = {
                device_name = "/dev/xvda"
                ebs = {
                  volume_size           = 50
                  volume_type           = "gp3"
                  iops                  = 3000
                  throughput            = 150
                  encrypted             = true
                  delete_on_termination = true
                }
              }
            }
            instance_types = ["t3.large"]
            capacity_type  = "SPOT"
            # 노드 그룹 생성시 아래의 옵션은 노드 생성 후 적용 필요
            # cluster-node join 이슈 발생됨 
            labels       = {
               "app.kubernetes.io/private-node" = "true"
            } 
          }
        }     
        cluster_addons = {
           coredns = {
               most_recent     = true
           }
           kube-proxy = {
               most_recent     = true
           }
           vpc-cni = {
               most_recent     = true
           }
        }
        cloudwatch_log_group_retention_in_days = "1"
      }
  }
}
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"
  for_each = local.eks

  cluster_name    = each.key
  cluster_version = each.value.cluster_version

  vpc_id          = each.value.vpc
  subnet_ids      = each.value.subnet_ids

  cluster_endpoint_public_access       = try(each.value.public_access, false)
  cluster_endpoint_public_access_cidrs = try(each.value.public_access_cidrs, [])

  eks_managed_node_group_defaults = {
    ami_type = "AL2023_x86_64_STANDARD"
  }

  eks_managed_node_groups = try(each.value.eks_managed_node_groups, {})

  cluster_addons = try(each.value.cluster_addons, {})

  enable_cluster_creator_admin_permissions = true

  cloudwatch_log_group_retention_in_days = each.value.cloudwatch_log_group_retention_in_days
}