locals {
  cluster_name = "llm-deploy-eks"
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
  name_prefix = "eks-worker-node-launch-template-"
  # image_id             = "ami-0b9c149e94f7ce9ed" 

  instance_type        = "t2.micro"
  key_name             = "personal-vm"  
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