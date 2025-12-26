data "aws_region" "current" {}

data "aws_iam_policy_document" "keda_sqs_policy_document" {
  statement {
    sid = "KedaSQSPolicy"
    effect = "Allow"

    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility"
    ]

    resources =  ["*"]
  }
}

