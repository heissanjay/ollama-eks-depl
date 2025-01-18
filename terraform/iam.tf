locals {
  karpenter_namespace            = "kube-system"
  karpenter_service_account_name = "karpenter"
}


resource "aws_iam_role" "eks_cluster_role" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Effect = "Allow"
          Principal = {
            Service = "eks.amazonaws.com"
          }
          Action = "sts:AssumeRole"
        }
      ]
    }
  )
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_ebs_block_storage_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSBlockStoragePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_compute_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSComputePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_network_policy_attachment" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSNetworkingPolicy"
}


resource "aws_iam_role" "eks_worker_node_role" {
  name = "eks-worker-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy_attachment" {
  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_worker_cni_policy_attachment" {
  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


resource "aws_iam_role_policy_attachment" "eks_worker_ec2_container_registry_policy_attachment" {
  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "eks_worker_vpc_policy_attachment" {
  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonVPCFullAccess"
}
data "tls_certificate" "eks_cluster" {
  url = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}
resource "aws_iam_openid_connect_provider" "eks_cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

data "aws_iam_policy_document" "karpenter_assume_role_policy" {
  statement {
    effect = "Allow"
    principals {
      type = "Federated"
      identifiers = [
        aws_iam_openid_connect_provider.eks_cluster.arn
      ]
    }
    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_service_account_name}"
      ]
    }
  }
}

data "aws_partition" "current" {}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "karpenter_execution_policy" {
  statement {
    sid = "AllowScopedEC2InstanceActions"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::image/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}::snapshot/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:security-group/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:subnet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
    ]
  }

  statement {
    sid = "AllowScopedEC2InstanceActionsWithTags"
    actions = [
      "ec2:RunInstances",
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowScopedResourceCreationTagging"
    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:fleet/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:spot-instances-request/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:volume/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:network-interface/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"

      values = [
        "RunInstances",
        "CreateFleet",
        "CreateLaunchTemplate"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowScopedResourceTagging"
    actions = [
      "ec2:CreateTags"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }

    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"

      values = [
        "karpenter.sh/nodeclaim",
        "Name"
      ]
    }
  }

  statement {
    sid = "AllowScopedDeletion"
    actions = [
      "ec2:TerminateInstances",
      "ec2:DeleteLaunchTemplate"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:instance/*",
      "arn:${data.aws_partition.current.partition}:ec2:${data.aws_region.current.name}:*:launch-template/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.sh/nodepool"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowRegionalReadActions"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"

      values = [
        data.aws_region.current.name
      ]
    }
  }

  statement {
    sid = "AllowSSMReadActions"
    actions = [
      "ssm:GetParameter"
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.name}::parameter/aws/service/*"
    ]
  }

  statement {
    sid = "AllowPricingReadActions"
    actions = [
      "pricing:GetProducts"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    sid = "AllowInterruptionQueueActions"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueUrl",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage"
    ]

    resources = [
      "arn:aws:sqs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${local.cluster_name}"
    ]
  }

  statement {
    sid = "AllowPassingInstanceRole"
    actions = [
      "iam:PassRole",
    ]

    resources = [aws_iam_role.eks_worker_node_role.arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"

      values = [
        "ec2.amazonaws.com"
      ]
    }
  }

  statement {
    sid = "AllowScopedInstanceProfileCreationActions"
    actions = [
      "iam:CreateInstanceProfile"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"

      values = [
        data.aws_region.current.name
      ]
    }


    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowScopedInstanceProfileTagActions"
    actions = [
      "iam:TagInstanceProfile"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"

      values = [
        data.aws_region.current.name
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/topology.kubernetes.io/region"

      values = [
        data.aws_region.current.name
      ]
    }


    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowScopedInstanceProfileActions"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:DeleteInstanceProfile"
    ]

    resources = [
      "*"
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/kubernetes.io/cluster/${local.cluster_name}"

      values = [
        "owned"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/topology.kubernetes.io/region"

      values = [
        data.aws_region.current.name
      ]
    }


    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass"

      values = [
        "*"
      ]
    }
  }

  statement {
    sid = "AllowInstanceProfileReadActions"
    actions = [
      "iam:GetInstanceProfile"
    ]

    resources = [
      "*"
    ]
  }

  statement {
    actions = [
      "eks:DescribeCluster",
    ]

    resources = [
      "arn:${data.aws_partition.current.partition}:eks:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:cluster/${local.cluster_name}",
    ]
  }
}

resource "aws_iam_role" "karpenter" {
  name_prefix = "karpenter-"


  assume_role_policy = data.aws_iam_policy_document.karpenter_assume_role_policy.json

  inline_policy {
    name   = "karpenter_execution_policy"
    policy = data.aws_iam_policy_document.karpenter_execution_policy.json
  }
}

resource "aws_iam_role_policy_attachment" "karpenter_ssm_policy" {
  role       = aws_iam_role.eks_worker_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = local.karpenter_namespace
  create_namespace = true

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "0.36.2"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.karpenter.arn
  }
  set {
    name  = "settings.clusterName"
    value = local.cluster_name
  }
  set {
    name  = "settings.clusterEndpoint"
    value = aws_eks_cluster.eks_cluster.endpoint
  }
}

output "karpenter_role_arn" {
  description = "The ARN of the IAM role for Karpenter"
  value       = aws_iam_role.karpenter.arn
}

output "cluster_name" {
  description = "The name of the EKS cluster"
  value       = local.cluster_name
}

output "cluster_endpoint" {
  description = "The endpoint of the EKS cluster's API server"
  value       = aws_eks_cluster.eks_cluster.endpoint
}