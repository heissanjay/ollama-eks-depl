locals {
  cluster_name                            = "llm-deploy-eks"
  ebs_csi_controller_service_account_name = "ebs-csi-controller-sa"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = local.cluster_name
  version  = "1.31"
  role_arn = aws_iam_role.eks_cluster_role.arn


  vpc_config {
    subnet_ids         = concat(aws_subnet.public_subnet[*].id, aws_subnet.private_subnet[*].id)
    security_group_ids = [aws_security_group.eks_cluster_sg.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy_attachment,
    aws_iam_role_policy_attachment.eks_service_policy_attachment,
    aws_iam_role_policy_attachment.eks_ebs_block_storage_policy_attachment,
    aws_iam_role_policy_attachment.eks_cni_policy_attachment,
    aws_iam_role_policy_attachment.eks_compute_policy_attachment,
    aws_iam_role_policy_attachment.eks_network_policy_attachment
  ]
}
data "template_file" "user_data" {
  template = <<-EOT
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="

--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"

#!/bin/bash
set -o xtrace

yum update -y
yum install -y aws-cli jq
/etc/eks/bootstrap.sh ${aws_eks_cluster.eks_cluster.name}

--==MYBOUNDARY==--
EOT
}


resource "aws_launch_template" "eks_launch_template" {
  name_prefix   = "eks-worker-node-launch-template-"
  instance_type = "t3.medium"
  key_name      = "personal-vm"

  vpc_security_group_ids = [aws_security_group.eks_worker_sg.id]

  user_data = base64encode(data.template_file.user_data.rendered)

}

resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "llm-deploy-eks-node-group"
  node_role_arn   = aws_iam_role.eks_worker_node_role.arn
  subnet_ids      = aws_subnet.private_subnet[*].id

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  launch_template {
    id      = aws_launch_template.eks_launch_template.id
    version = "$Latest"
  }

  depends_on = [aws_eks_cluster.eks_cluster]

  tags = {
    "Name" = "eks-node-group"
  }
}

data "aws_eks_cluster_auth" "eks_cluster_auth" {
  name = aws_eks_cluster.eks_cluster.name
}

resource "kubernetes_config_map" "aws_auth" {
  metadata {
    name      = "aws-auth"
    namespace = "kube-system"
  }

  data = {
    mapRoles = <<EOF
    - rolearn: ${aws_iam_role.eks_worker_node_role.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
    EOF
  }

  depends_on = [aws_eks_node_group.eks_node_group]
}

data "aws_default_tags" "current" {}

data "aws_iam_policy_document" "ebs_csi_controller_assume_role_policy" {
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
      variable = "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values = [
        "sts.amazonaws.com"
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:kube-system:${local.ebs_csi_controller_service_account_name}"
      ]
    }
  }
}

resource "kubernetes_storage_class" "gp3_encrypted" {
  metadata {
    name = "gp3-encrypted"
  }
  storage_provisioner = "ebs.csi.aws.com"
  volume_binding_mode = "WaitForFirstConsumer"
  reclaim_policy      = "Delete"
  parameters = merge(
    { for i, key in keys(data.aws_default_tags.current.tags) : "tagSpecification_${i}" => "${key}=${data.aws_default_tags.current.tags[key]}" },
    {
      type      = "gp3"
      fsType    = "ext4"
      encrypted = "true"
    }
  )
}

resource "aws_iam_role" "ebs_csi_controller" {
  name_prefix = "ebs-csi-controller-"

  assume_role_policy = data.aws_iam_policy_document.ebs_csi_controller_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ebs_csi_controller_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi_controller.name
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name  = aws_eks_cluster.eks_cluster.name
  addon_name    = "aws-ebs-csi-driver"
  addon_version = "v1.38.1-eksbuild.1"

  service_account_role_arn = aws_iam_role.ebs_csi_controller.arn
}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "vpc-cni"
  addon_version     = "v1.19.0-eksbuild.1"
  resolve_conflicts = "OVERWRITE"
}


resource "aws_eks_addon" "coredns" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "coredns"
  addon_version     = "v1.11.4-eksbuild.2"
  resolve_conflicts = "OVERWRITE"
}


resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = aws_eks_cluster.eks_cluster.name
  addon_name        = "kube-proxy"
  addon_version     = "v1.31.3-eksbuild.2"
  resolve_conflicts = "OVERWRITE"
}

