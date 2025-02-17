
# Spring Boot 애플리케이션 배포 및 EKS 설정

## 개요
본 문서는 Spring Boot 애플리케이션의 Docker 이미지를 제작하고, GitHub Container Registry(GHCR)에 업로드하는 방법을 설명합니다. 또한, AWS 환경에서 Terraform을 활용하여 VPC 및 EKS를 구성하고, Helm을 사용하여 AWS Load Balancer Controller를 설치하는 방법을 포함합니다.

## 1. Spring Boot 애플리케이션 개발 및 Dockerfile 작성

### 1.1 Spring Boot 애플리케이션
Spring Boot 애플리케이션을 개발하고, `index.html`을 포함한 프로젝트를 구성합니다.

### 1.2 Dockerfile 작성
`Dockerfile`을 프로젝트 루트 디렉토리에 작성합니다.

```Dockerfile
FROM openjdk:17-jdk-alpine

ADD /build/libs/*.jar app.jar

ENTRYPOINT ["java","-jar","/app.jar"]
```

## 2. Docker 이미지 빌드 및 GitHub Container Registry 업로드

### 2.1 Spring Boot 애플리케이션 빌드
```sh
sh gradlew --no-daemon clean build
```

### 2.2 Docker 이미지 빌드
```sh
docker build -t springboot-docker .
```

### 2.3 GitHub Container Registry 로그인
먼저, GitHub Personal Access Token(PAT)을 사용하여 로그인합니다. 자세한 내용은 [GitHub Container Registry 공식 문서](https://docs.github.com/ko/packages/working-with-a-github-packages-registry/working-with-the-container-registry)를 참고하세요.
```sh
echo "<GITHUB_PAT>" | docker login ghcr.io -u <GITHUB_USERNAME> --password-stdin
```

### 2.4 Docker 이미지 태깅 및 푸시
```sh
docker tag springboot-docker:latest ghcr.io/<GITHUB_USERNAME>/springboot-docker:latest
docker push ghcr.io/<GITHUB_USERNAME>/springboot-docker:latest
```

[제작된 이미지](https://github.com/users/Koorovider/packages/container/package/springboot-docker)

## 3. AWS Terraform 구성

### 3.1 VPC 구성
```hcl
locals {
  vpc = {
    "sdxx365-vpc" = {
      cidr  = "10.21.0.0/16"
      enable_nat_gateway = true
      azs   = ["ap-northeast-2a", "ap-northeast-2b"]

      private = {
        subnets = ["10.21.0.0/24", "10.21.1.0/24"]
        tags    = {
          "kubernetes.io/role/internal-elb" = 1
        }
      }

      public = {
        subnets = ["10.21.32.0/24", "10.21.33.0/24"]
        tags    = {
          "kubernetes.io/role/elb" = 1
        }
      }
      tags = {
        terraform-aws-modules = "vpc"
      }
    }
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  for_each = local.vpc

  name = each.key
  cidr = each.value.cidr

  azs             = try(each.value.azs, [])
  private_subnets = try(each.value.private.subnets, [])
  public_subnets  = try(each.value.public.subnets, [])

  enable_nat_gateway = try(each.value.enable_nat_gateway, false)

  private_subnet_tags = try(each.value.private.tags, {})
  public_subnet_tags  = try(each.value.public.tags, {})

  tags = try(each.value.tags, {})
}
```

### 3.2 EKS 클러스터 구성
```hcl
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
```

## 4. AWS Load Balancer Controller 설치

### 4.1 AWS Load Balancer Controller 설치
Helm을 사용하여 AWS Load Balancer Controller를 설치합니다. [참고](https://docs.aws.amazon.com/ko_kr/eks/latest/userguide/lbc-helm.html#lbc-helm-iam)


## 5. Spring Boot 애플리케이션 배포

### 5.1 Spring Boot 애플리케이션 배포 YAML 파일 작성
다음은 Spring Boot 애플리케이션을 Kubernetes에 배포하기 위한 YAML 파일입니다. 이 파일을 통해 `Namespace`, `Deployment`, `Service`, `Ingress` 리소스를 정의합니다.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: springboot-test
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: springboot-deployment
  namespace: springboot-test  
  labels:
    app: springboot-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: springboot-app
  template:
    metadata:
      labels:
        app: springboot-app
    spec:
      containers:
        - name: springboot-container
          image: ghcr.io/koorovider/springboot-docker:latest
          ports:
            - containerPort: 8080    
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: "app.kubernetes.io/private-node"
                    operator: In
                    values:
                      - "true"
---
apiVersion: v1
kind: Service
metadata:
  name: springboot-service
  namespace: springboot-test  
spec:
  selector:
    app: springboot-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP            
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: springboot-ingress
  namespace: springboot-test  
  annotations:
    kubernetes.io/ingress.class: alb  
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  labels:
    app: springboot-app
spec:
  ingressClassName: alb
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: springboot-service
                port:
                  number: 80
```

### 5.2 Kubernetes 리소스 적용
작성한 YAML 파일을 사용하여 Kubernetes 클러스터에 리소스를 배포합니다.

```bash
kubectl apply -f springboot-app.yaml
```

## ALB 확인
![확인](https://github.com/Koorovider/example/blob/main/image/%ED%99%95%EC%9D%B8.PNG)

## 최종 결과 : 
![결과](https://github.com/Koorovider/example/blob/main/image/%EA%B2%B0%EA%B3%BC.PNG)



