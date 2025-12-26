locals {
  eks_managed_node_groups = {
    main-node-group = {
      name           = "main-node-group"
      max_size       = 3
      desired_size   = 2
      min_size       = 2
      instance_types = ["t3.medium"]

      # taints = {
      #   addons = {
      #     key    = "CriticalAddonsOnly"
      #     value  = "true"
      #     effect = "NO_SCHEDULE"
      #   },
      # }
    }
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>21.0"

  name               = "${local.app_name}-eks"
  kubernetes_version = "1.32"

  enable_cluster_creator_admin_permissions = true
  endpoint_public_access                   = true
  endpoint_private_access                  = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  addons = {
    coredns = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
  }

  eks_managed_node_groups = local.eks_managed_node_groups
}
