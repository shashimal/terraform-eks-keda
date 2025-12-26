locals {
  keda_namespace = "keda-system"
}

resource "kubernetes_namespace_v1" "ns_keda" {
  metadata {
    name = local.keda_namespace
    labels = {
      name = local.keda_namespace
    }
  }
}

module "keda_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.0"

  name = "eks-keda-sqs-irsa"
  policies = {
    sqs_policy = aws_iam_policy.keda_sqs_policy.arn
  }

  oidc_providers = {
    eks = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = [
        "${local.keda_namespace}:keda-operator"
      ]
    }
  }

  tags = {
    Purpose = "KEDA SQS autoscaling"
  }

  depends_on = [kubernetes_namespace_v1.ns_keda]
}

resource "aws_iam_policy" "keda_sqs_policy" {
  name = "keda-sqs-policy"
  policy = data.aws_iam_policy_document.keda_sqs_policy_document.json
}

resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.12.1"
  namespace = local.keda_namespace

  values = [
    yamlencode({
      serviceAccount = {
        operator = {
          create = true
          name   = "keda-operator"
          annotations = {
            "eks.amazonaws.com/role-arn" = module.keda_irsa.arn
          }
        }
        metricServer = {
          create = true
          name   = "keda-metrics-apiserver"
        }
        webhooks = {
          create = true
          name   = "keda-admission-webhooks"
        }
      }

      podIdentity = {
        aws = {
          irsa = {
            enabled = true
          }
        }
      }

      # Resource limits and requests
      resources = {
        operator = {
          limits = {
            cpu    = "1"
            memory = "1000Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "100Mi"
          }
        }
        metricServer = {
          limits = {
            cpu    = "1"
            memory = "1000Mi"
          }
          requests = {
            cpu    = "100m"
            memory = "100Mi"
          }
        }
        webhooks = {
          limits = {
            cpu    = "50m"
            memory = "100Mi"
          }
          requests = {
            cpu    = "10m"
            memory = "10Mi"
          }
        }
      }

      # Security context
      securityContext = {
        operator = {
          capabilities = {
            drop = ["ALL"]
          }
          allowPrivilegeEscalation = false
          readOnlyRootFilesystem   = true
          seccompProfile = {
            type = "RuntimeDefault"
          }
        }
      }

      # Logging configuration
      logging = {
        operator = {
          level  = "info"
          format = "console"
        }
        metricServer = {
          level = 0
        }
      }
    })
  ]

  depends_on = [
    module.eks,
    kubernetes_namespace_v1.ns_keda,
    module.keda_irsa
  ]
}

resource "time_sleep" "wait_for_keda" {
  depends_on      = [helm_release.keda]
  create_duration = "60s"
}
