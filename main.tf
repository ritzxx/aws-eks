locals {
  # enforce usage of eks_worker_ami_name_filter variable to set the right kubernetes version for EKS workers,
  # otherwise the first version of Kubernetes supported by AWS (v1.11) for EKS workers will be used, but
  # EKS control plane will use the version specified by kubernetes_version variable.
  eks_worker_ami_name_filter = "amazon-eks-node-${var.kubernetes_version}*"
  cluster_name               = module.eks_cluster.eks_cluster_id
  kubernetes_config_map_id   = module.eks_cluster.kubernetes_config_map_id
}

module "vpc" {
  source     = "github.com/Greg215/terraform-aws-eks//vpc?ref=main"
  cidr_block = "172.31.216.0/22"
  name       = "test-vpc"
}

module "subnets" {
  source              = "github.com/Greg215/terraform-aws-eks//subnet?ref=main"
  vpc_id              = module.vpc.vpc_id
  igw_id              = module.vpc.igw_id
  nat_gateway_enabled = false
  name                = "test-subnets"
}

module "network_loadbalancer" {
  source                         = "github.com/Greg215/terraform-aws-eks//nlb?ref=main"
  name                           = "ritz-nlb-eks"
  vpc_id                         = module.vpc.vpc_id
  vpc_public_subnet_ids          = module.subnets.public_subnet_ids
  aws-load-balancer-ssl-cert-arn = "arn:aws:acm:ap-southeast-1:545573948854:certificate/9e9ef1d3-1913-419f-9a9d-72e4c96acfc4"
  listeners = [
    {
      port     = 80
      protocol = "TCP",
      target_groups = {
        port              = 30080
        proxy_protocol    = false
        health_check_port = "traffic-port"
      }
    },
    {
      port     = 443
      protocol = "TLS",
      target_groups = {
        port              = 30080
        proxy_protocol    = false
        health_check_port = "traffic-port"
      }
    }
  ]
  security_group_for_eks = [
    {
      port_from  = 0
      port_to    = 65535
      protocol   = "-1"
      cidr_block = ["0.0.0.0/0"]
    }
  ]
}

module "eks_cluster" {
  source                     = "github.com/Greg215/terraform-aws-eks//eks-cluster?ref=main"
  name                       = "ritz-eks-cluster"
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.subnets.public_subnet_ids
  kubernetes_version         = var.kubernetes_version
  oidc_provider_enabled      = false
  workers_role_arns          = [module.eks_workers.workers_role_arn]
  workers_security_group_ids = [module.eks_workers.security_group_id]
}

module "eks_workers" {
  source                                 = "github.com/Greg215/terraform-aws-eks//eks-worker?ref=main"
  name                                   = module.eks_cluster.eks_cluster_id
  key_name                               = var.key_name
  image_id                               = var.image_id
  instance_type                          = var.instance_type
  vpc_id                                 = module.vpc.vpc_id
  subnet_ids                             = module.subnets.public_subnet_ids
  min_size                               = var.min_size
  max_size                               = var.max_size
  cluster_name                           = module.eks_cluster.eks_cluster_id
  cluster_endpoint                       = module.eks_cluster.eks_cluster_endpoint
  cluster_certificate_authority_data     = module.eks_cluster.eks_cluster_certificate_authority_data
  cluster_security_group_id              = var.cluster_security_group_id
  additional_security_group_ids          = [module.network_loadbalancer.security_group_k8s]
  cluster_security_group_ingress_enabled = var.cluster_security_group_ingress_enabled
  associate_public_ip_address            = true
  autoscaling_policies_enabled           = true
  target_group_arns                      = concat(module.network_loadbalancer.target_group_arns)
}

module "route53" {
  source  = "github.com/Greg215/terraform-aws-eks//route53-records?ref=main"
  zone_id = "Z07374591FC76OBQXEXUL"
  type    = "CNAME"
  records = [
    {
      NAME   = "ritz.training.visiontech.com.sg"
      RECORD = module.network_loadbalancer.dns_name
      TTL    = "300"
    },
    {
      NAME   = "hazelcast-ritz.training.visiontech.com.sg"
      RECORD = module.network_loadbalancer.dns_name
      TTL    = "300"
    },
    {
      NAME   = "dashboard-ritz.training.visiontech.com.sg"
      RECORD = module.network_loadbalancer.dns_name
      TTL    = "300"
    },
    {
      NAME   = "jenkins-ritz.training.visiontech.com.sg"
      RECORD = module.network_loadbalancer.dns_name
      TTL    = "300"
    }
  ]
}
