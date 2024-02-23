#!/bin/bash

# Variables
CLUSTER_NAME=robot-eks-argo
REGION=us-west-1
NODE_NAME=robot-linux-nodes
KEY_NAME=robot-app-key

# Set AWS credentials before script execution

aws sts get-caller-identity >> /dev/null
if [ $? -eq 0 ]
then
  echo "Credentials tested, proceeding with the cluster creation."

  # Creation of EKS cluster
  eksctl create cluster \
  --name $CLUSTER_NAME \
  --version 1.29 \
  --region $REGION \
  --nodegroup-name $NODE_NAME \
  --nodes 2 \
  --nodes-min 2 \
  --nodes-max 4 \
  --node-type t2.large \
  --node-volume-size 20 \
  --ssh-access \
  --ssh-public-key $KEY_NAME \
  --managed
  if [ $? -eq 0 ]
  then
    echo "Cluster Setup Completed with eksctl command."
  else
    echo "Cluster Setup Failed while running eksctl command."
  fi
else
  echo "Please run aws configure & set right credentials."
  echo "Cluster setup failed."
fi

kubectl get nodes

oidc_id=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | cut -d '/' -f 5)

aws iam list-open-id-connect-providers | grep $oidc_id | cut -d "/" -f4

eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME--approve

# ALB configuration

curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.5.4/docs/install/iam_policy.json

aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://iam_policy.json

eksctl create iamserviceaccount --cluster=$CLUSTER_NAME --namespace=kube-system --name=aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole --attach-policy-arn=arn:aws:iam::160202668836:policy/AWSLoadBalancerControllerIAMPolicy --approve

helm repo add EKS https://aws.github.io/eks-charts

helm repo update EKS

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=robot-eks-argo \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=vpc-02caea3263e2e9b96

sleep 10

kubectl get deployment -n kube-system aws-load-balancer-controller

eksctl create iamserviceaccount \
    --name ebs-csi-controller-sa \
    --namespace kube-system \
    --cluster $CLUSTER_NAME \
    --role-name AmazonEKS_EBS_CSI_DriverRole \
    --role-only \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy \
    --approve


eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER_NAME --service-account-role-arn arn:aws:iam::160202668836:role/AmazonEKS_EBS_CSI_DriverRole --force

# verify EBS CSI driver installed or not

echo "See below output if EBS CSI driver installed or not"

eksctl get addon --cluster robot-eks-argo | grep ebs
