locals {
  app_name = "keda-sqs"
}

resource "kubernetes_namespace_v1" "app_ns" {
  metadata {
    name = local.app_name
    labels = {
      name = local.app_name
    }
  }
}

module "app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "${local.app_name}-irsa"
  policies = {
    sqs_policy = aws_iam_policy.keda_sqs_policy.arn
  }

  oidc_providers = {
    eks = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${local.app_name}:${local.app_name}-sa"
      ]
    }
  }

  tags = {
    Purpose = "KEDA SQS autoscaling"
  }
}

resource "kubernetes_service_account_v1" "app_sa" {
  metadata {
    name      = "${local.app_name}-sa"
    namespace = local.app_name

    annotations = {
      "eks.amazonaws.com/role-arn" = module.app_irsa.arn
    }
  }
}

resource "aws_sqs_queue" "app_sqs" {
  name = local.app_name
}