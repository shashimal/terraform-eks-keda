# Auto-scaling Kubernetes Workloads with KEDA and Amazon SQS

## Introduction

Kubernetes Event-Driven Autoscaling (KEDA) is a powerful tool that enables event-driven autoscaling for Kubernetes workloads. Unlike traditional Horizontal Pod Autoscaler (HPA) that relies on CPU and memory metrics, KEDA can scale applications based on external metrics such as message queue length, database connections, or custom metrics from various sources.

In this article, we'll explore a complete implementation of KEDA with Amazon SQS (Simple Queue Service) on Amazon EKS, demonstrating how to build a scalable, event-driven architecture that automatically adjusts pod replicas based on queue depth.

## Architecture Overview

Our implementation consists of several key components:

1. **Amazon EKS Cluster** - Managed Kubernetes cluster
2. **KEDA Operator** - Event-driven autoscaling controller
3. **Amazon SQS Queue** - Message queue for triggering scaling events
4. **Consumer Application** - Kubernetes deployment that processes SQS messages
5. **IAM Roles and Service Accounts** - Security layer using IRSA (IAM Roles for Service Accounts)

## Infrastructure Components

### VPC and Networking

The foundation starts with a well-architected VPC setup:

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~>6.4"

  name = "${local.app_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true
}
```

This creates a multi-AZ VPC with both public and private subnets, ensuring high availability and proper network isolation.

### EKS Cluster Configuration

The EKS cluster is configured with essential add-ons and managed node groups:

```hcl
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~>21.0"

  name               = "${local.app_name}-eks"
  kubernetes_version = "1.32"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  addons = {
    coredns                = {}
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy            = {}
    vpc-cni               = { before_compute = true }
  }

  eks_managed_node_groups = {
    main-node-group = {
      max_size       = 3
      desired_size   = 2
      min_size       = 2
      instance_types = ["t3.medium"]
    }
  }
}
```

## KEDA Installation and Configuration

### IRSA Setup for KEDA

Security is paramount in our implementation. We use IAM Roles for Service Accounts (IRSA) to provide KEDA with the necessary permissions to interact with SQS:

```hcl
module "keda_irsa" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"

  name = "eks-keda-sqs-irsa"
  policies = {
    sqs_policy = aws_iam_policy.keda_sqs_policy.arn
  }

  oidc_providers = {
    eks = {
      provider_arn = module.eks.oidc_provider_arn
      namespace_service_accounts = ["keda:keda-operator"]
    }
  }
}
```

The IAM policy grants KEDA the minimum required permissions:

```hcl
data "aws_iam_policy_document" "keda_sqs_policy_document" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility"
    ]
    resources = ["*"]
  }
}
```

### KEDA Helm Installation

KEDA is deployed using Helm with comprehensive configuration:

```hcl
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "2.18.0"
  namespace  = "keda"

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
      }

      podIdentity = {
        aws = {
          irsa = { enabled = true }
        }
      }

      resources = {
        operator = {
          limits   = { cpu = "1", memory = "1000Mi" }
          requests = { cpu = "100m", memory = "100Mi" }
        }
      }
    })
  ]
}
```

## Application Setup

### Consumer Application

The consumer application is a simple deployment that simulates SQS message processing:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sqs-consumer
  namespace: keda-sqs
spec:
  replicas: 1
  selector:
    matchLabels:
      app: sqs-consumer
  template:
    metadata:
      labels:
        app: sqs-consumer
    spec:
      serviceAccountName: keda-sqs-sa
      containers:
        - name: worker
          image: public.ecr.aws/docker/library/busybox
          command:
            - sh
            - -c
            - |
              while true; do
                echo "Processing SQS message..."
                sleep 10
              done
```

### KEDA ScaledObject Configuration

The heart of our autoscaling setup is the ScaledObject resource:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: aws-sqs-queue-scaledobject
  namespace: keda-sqs
spec:
  scaleTargetRef:
    name: sqs-consumer
  triggers:
    - type: aws-sqs-queue
      authenticationRef:
        name: aws-trigger-auth
      metadata:
        queueURL: https://sqs.ap-southeast-1.amazonaws.com/793209430381/keda-sqs
        queueLength: "5"
        awsRegion: "ap-southeast-1"
```

This configuration tells KEDA to:
- Monitor the specified SQS queue
- Scale the `sqs-consumer` deployment
- Trigger scaling when queue length exceeds 5 messages
- Use AWS authentication via IRSA

### Authentication Configuration

The TriggerAuthentication resource enables KEDA to authenticate with AWS:

```yaml
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: aws-trigger-auth
  namespace: keda-sqs
spec:
  podIdentity:
    provider: aws
```

## How It Works

1. **Message Arrival**: Messages arrive in the SQS queue
2. **KEDA Monitoring**: KEDA operator continuously polls the queue to check message count
3. **Scaling Decision**: When queue length exceeds the threshold (5 messages), KEDA calculates the desired replica count
4. **Pod Scaling**: KEDA creates additional pod replicas to handle the increased load
5. **Scale Down**: When the queue is empty or below threshold, KEDA scales down the deployment

## Key Benefits

### Event-Driven Scaling
Unlike traditional CPU/memory-based scaling, this approach scales based on actual workload demand represented by queue depth.

### Cost Optimization
Pods scale to zero when there's no work, minimizing resource costs during idle periods.

### Security Best Practices
- Uses IRSA for secure AWS API access
- Follows principle of least privilege
- No hardcoded credentials

### Operational Simplicity
- Declarative configuration
- Automatic scaling without manual intervention
- Built-in monitoring and observability

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                           AWS Account                            │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────────┐│
│  │                        VPC (10.0.0.0/16)                   ││
│  │                                                             ││
│  │  ┌─────────────────┐              ┌─────────────────────────┐││
│  │  │  Public Subnet  │              │    Private Subnet       │││
│  │  │  (NAT Gateway)  │              │                         │││
│  │  └─────────────────┘              │  ┌─────────────────────┐│││
│  │                                   │  │    EKS Cluster      ││││
│  │                                   │  │                     ││││
│  │  ┌─────────────────────────────────┐  │  ┌─────────────────┐││││
│  │  │         Amazon SQS              │  │  │  KEDA Namespace ││││
│  │  │                                 │  │  │                 ││││
│  │  │  ┌─────────────────────────────┐│  │  │  ┌─────────────┐││││
│  │  │  │      keda-sqs Queue         ││  │  │  │KEDA Operator│││││
│  │  │  │                             ││  │  │  │             │││││
│  │  │  │  Messages: [msg1][msg2]...  ││  │  │  │   Monitors  │││││
│  │  │  │                             ││  │  │  │   SQS Queue │││││
│  │  │  └─────────────────────────────┘│  │  │  └─────────────┘││││
│  │  └─────────────────────────────────┘  │  └─────────────────┘│││
│  │                    │                  │                     │││
│  │                    │ Polls Queue      │  ┌─────────────────┐│││
│  │                    │ Depth            │  │ App Namespace   ││││
│  │                    │                  │  │                 ││││
│  │                    └──────────────────┼──┤  ┌─────────────┐││││
│  │                                       │  │  │SQS Consumer ││││
│  │  ┌─────────────────────────────────────┐  │  │ Deployment  ││││
│  │  │            IAM Role                 │  │  │             ││││
│  │  │                                     │  │  │ Replicas:   ││││
│  │  │  ┌─────────────────────────────────┐│  │  │ 0 → N       ││││
│  │  │  │     KEDA SQS Policy             ││  │  │ (Auto-scale)││││
│  │  │  │                                 ││  │  └─────────────┘││││
│  │  │  │ - sqs:GetQueueAttributes        ││  │                 │││
│  │  │  │ - sqs:ReceiveMessage            ││  └─────────────────┘││
│  │  │  │ - sqs:DeleteMessage             ││                     ││
│  │  │  └─────────────────────────────────┘│                     ││
│  │  └─────────────────────────────────────┘                     ││
│  │                    │                                          ││
│  │                    │ IRSA (IAM Roles for Service Accounts)   ││
│  │                    │                                          ││
│  └────────────────────┼──────────────────────────────────────────┘│
└───────────────────────┼───────────────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   Scaling Logic     │
              │                     │
              │ Queue Length > 5    │
              │ ──────────────────► │
              │ Scale Up Pods       │
              │                     │
              │ Queue Length = 0    │
              │ ──────────────────► │
              │ Scale Down to 0     │
              └─────────────────────┘
```

## Conclusion

This KEDA and SQS implementation demonstrates a robust, scalable, and cost-effective approach to event-driven autoscaling in Kubernetes. By leveraging AWS managed services and cloud-native tools, we've created a system that automatically adapts to workload demands while maintaining security and operational best practices.

The combination of KEDA's flexibility with SQS's reliability provides a solid foundation for building responsive, event-driven applications that can handle varying loads efficiently and cost-effectively.
