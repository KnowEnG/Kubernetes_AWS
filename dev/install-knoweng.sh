read -p 'S3 bucket for new state store (e.g., knowdevkops-state-store): ' STATESTORE
read -p 'Path to SSL key: ' SSL_KEY_PATH
read -p 'Path to SSL cert: ' SSL_CRT_PATH
read -p 'DNS name of server (must match cert): ' SERVER_DNS_NAME

# IF CHANGING VERSIONS, YOU MIGHT ALSO NEED TO CHANGE CONFIG PASSED TO KOPS AND KUBECTL

# note: version in August was 1.10.0
KOPS_VERSION=1.11.1

# note: version in August was 1.11.2
KUBERNETES_VERSION=1.11.9

# see the table at
# https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases
# to find a version compatible with KUBERNETES_VERSION
CLUSTER_AUTOSCALER_VERSION=1.3.9

# see https://github.com/kubernetes-incubator/external-storage/releases
# to find a version compatible with KUBERNETES_VERSION
EXTERNAL_STORAGE_VERSION=5.1.0

curl -sSL -o kops https://github.com/kubernetes/kops/releases/download/$KOPS_VERSION/kops-linux-amd64 && \
  chmod +x ./kops && \
  sudo mv ./kops /usr/local/bin/
if [ $? -eq 0 ]
  then
    echo "kops installed"
  else
    echo "kops installation failed; exiting"
    exit
fi

curl -sSL -o kubectl https://storage.googleapis.com/kubernetes-release/release/v$KUBERNETES_VERSION/bin/linux/amd64/kubectl && \
  chmod +x ./kubectl && \
  sudo mv ./kubectl /usr/local/bin/kubectl
if [ $? -eq 0 ]
  then
    echo "kubectl installed"
  else
    echo "kubectl installation failed; exiting"
    exit
fi

sudo apt-get -qq install awscli
if [ $? -eq 0 ]
  then
    echo "awscli installed"
  else
    echo "awscli installation failed; exiting"
    exit
fi

# note: creating the bucket in us-east-1, because the location doesn't much matter
# if creating the bucket in any other region, add "--create-bucket-configuration LocationConstraint=<region>"
# you'll also need to update uninstall-knoweng.sh, which assumes the s3 bucket is in us-east-1
aws s3api create-bucket \
  --bucket $STATESTORE \
  --region us-east-1
if [ $? -eq 0 ]
  then
    echo "state store created"
  else
    echo "state store creation failed; exiting"
    exit
fi

aws s3api put-bucket-versioning --bucket $STATESTORE --versioning-configuration Status=Enabled
if [ $? -eq 0 ]
  then
    echo "state store versioned"
  else
    echo "state store versioning failed; exiting"
    exit
fi

ssh-keygen -t rsa -b 4096 -N '' -f "$HOME/.ssh/id_rsa" -q
if [ $? -eq 0 ]
  then
    echo "key created"
  else
    echo "key creation failed; exiting"
    exit
fi

export NAME=knowdev.k8s.local
export KOPS_STATE_STORE=s3://$STATESTORE
export REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`
export ZONES=$(aws ec2 describe-availability-zones --region $REGION | grep ZoneName | awk '{print $2}' | tr -d '"' | xargs | tr " " ",")

# PRAMOD SAYS: masters will not boot on M5 and C5 instance types but may have changed.
# PRAMOD SAYS: consider using --vpc: string Set to use a shared VPC and many other KOPS 
#              flags for helm & cfn setup
# note: if changing node-count, you'll have to adjust the logic that applies the
# pipelines_jobs and has_dns labels; there should be just one node with has_dns, but
# all nodes should have pipelines_jobs
kops create cluster $NAME \
  --zones $ZONES \
  --authorization RBAC \
  --master-size c4.large \
  --master-volume-size 100 \
  --node-size c4.xlarge \
  --node-volume-size 50 \
  --node-count 1 \
  --kubernetes-version $KUBERNETES_VERSION \
  --dry-run \
  -oyaml | \
  sed -e "s/nodes: public/nodes: public\n  additionalPolicies:\n    node: |\n      [\n        {\n          \"Effect\": \"Allow\",\n          \"Action\": [\n            \"autoscaling:DescribeAutoScalingGroups\",\n            \"autoscaling:DescribeAutoScalingInstances\",\n            \"autoscaling:DescribeTags\",\n            \"autoscaling:DescribeLaunchConfigurations\",\n            \"autoscaling:SetDesiredCapacity\",\n            \"autoscaling:TerminateInstanceInAutoScalingGroup\",\n            \"ec2:DescribeLaunchTemplateVersions\"\n          ],\n          \"Resource\": \"*\"\n        }\n      ]/" | \
  kops create -f - \
  && kops create secret --name $NAME sshpublickey admin -i "$HOME/.ssh/id_rsa.pub" \
  && kops update cluster $NAME --yes
if [ $? -eq 0 ]
  then
    echo "cluster creation initiated"
  else
    echo "cluster creation failed; exiting"
    exit
fi

kops validate cluster
while [ $? -ne 0 ]; do
  echo "checking cluster again in 15 seconds (expected total time ~4 min)"
  sleep 15s
  kops validate cluster
done

kops create ig pipes1 --dry-run -oyaml | \
  sed \
    -e "s/machineType: t2.medium/machineType: c4.xlarge/" \
    -e "s/maxSize: 2/maxSize: 1/" \
    -e "s/minSize: 2/minSize: 1/" \
    -e "s/nodeLabels:/nodeLabels:\n    pipelines_jobs: \"true\"/" | \
  kops create -f -
if [ $? -eq 0 ]
  then
    echo "pipes1 configured"
  else
    echo "pipes1 configuration failed; exiting"
    exit
fi

kops create ig pipes2 --dry-run -oyaml | \
  sed \
    -e "s/machineType: t2.medium/machineType: c4.8xlarge/" \
    -e "s/maxSize: 2/maxSize: 5/" \
    -e "s/minSize: 2/minSize: 0/" \
    -e "s/nodeLabels:/nodeLabels:\n    pipelines_jobs: \"true\"/" \
    -e "s/role: Node/role: Node\n  taints:\n  - dedicated=pipelines_jobs:NoSchedule/" | \
  kops create -f -
if [ $? -eq 0 ]
  then
    echo "pipes2 configured"
  else
    echo "pipes2 configuration failed; exiting"
    exit
fi

kops update cluster $NAME --yes
if [ $? -eq 0 ]
  then
    echo "instance groups created"
  else
    echo "instance groups creation failed; exiting"
    exit
fi

curl -sSL https://raw.githubusercontent.com/kubernetes/autoscaler/cluster-autoscaler-$CLUSTER_AUTOSCALER_VERSION/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-one-asg.yaml | \
  sed -e "s/nodes=1:10:k8s-worker-asg-1/nodes=0:5:pipes2.$NAME\n          env:\n            - name: AWS_REGION\n              value: $REGION/" | \
  kubectl apply -f -
if [ $? -eq 0 ]
  then
    echo "autoscaler created"
  else
    echo "autoscaler creation failed; exiting"
    exit
fi

export DNS_NODE=$(kubectl get nodes --selector=kops.k8s.io\/instancegroup=nodes -ojsonpath='{.items[0].metadata.name}')
kubectl label node $DNS_NODE has-dns=true && kubectl label node $DNS_NODE pipelines_jobs=true
if [ $? -eq 0 ]
  then
    echo "DNS node designated"
  else
    echo "DNS node designation failed; exiting"
    exit
fi

DNS_NODE_ID=$(kubectl get node $DNS_NODE -ojsonpath='{.spec.providerID}' | sed -e "s/^.*\///")

EFS_CREATION_DATA=$(aws efs create-file-system --creation-token $(uuidgen) --region $REGION)
if [ $? -eq 0 ]
  then
    echo "EFS created"
  else
    echo "EFS creation failed; exiting"
    exit
fi

EFS_ID=$(echo $EFS_CREATION_DATA | sed -e "s/^.*FileSystemId\": \"//" -e "s/\".*$//")

# NOTE: newer versions of awscli can set tags while creating the EFS
aws efs create-tags --file-system-id $EFS_ID --tags Key=Name,Value=EFS-for-${SERVER_DNS_NAME}-$(date +%F) --region $REGION

EFS_VPC_ID=$(aws ec2 describe-instances --instance-ids $DNS_NODE_ID --region $REGION --query "Reservations[0].Instances[0].NetworkInterfaces[0].VpcId" --output text)
EFS_SG_ID=$(aws ec2 describe-instances --instance-ids $DNS_NODE_ID --region $REGION --query "Reservations[0].Instances[0].NetworkInterfaces[0].Groups[0].GroupId" --output text)
EFS_SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$EFS_VPC_ID --region $REGION --query "Subnets[*].SubnetId" --output text)

for EFS_SUBNET_ID in $EFS_SUBNET_IDS ; do
  aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $EFS_SUBNET_ID --security-groups $EFS_SG_ID --region $REGION
done

while [ $(echo $EFS_SUBNET_IDS | wc -w) -ne $(aws efs describe-mount-targets --file-system-id $EFS_ID --region $REGION --query "length(MountTargets[?LifeCycleState=='available'])") ]; do
  echo "checking mount targets again in 15s"
  sleep 15s
done
echo "mount targets ready"

EFS_DNS=${EFS_ID}.efs.${REGION}.amazonaws.com

curl -s https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/common/efs-provisioner.yaml | \
  sed -e "s/EFS_DNS/$EFS_DNS/" -e "s/EFS_ID/$EFS_ID/" -e "s/EFS_REGION/$REGION/" | \
  kubectl apply -f -
if [ $? -eq 0 ]
  then
    echo "provisioner created"
  else
    echo "provisioner creation failed; exiting"
    exit
fi

kubectl apply -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/v$EXTERNAL_STORAGE_VERSION/aws/efs/deploy/rbac.yaml
if [ $? -eq 0 ]
  then
    echo "provisioner rbac applied"
  else
    echo "provisioner rbac application failed; exiting"
    exit
fi

kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/networks.pvc.yaml && \
  kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/postgres.pvc.yaml && \
  kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/userfiles.pvc.yaml
if [ $? -eq 0 ]
  then
    echo "pvcs created"
  else
    echo "pvc creation failed; exiting"
    exit
fi

MASTER_IP=$(kubectl get nodes --selector=kubernetes.io\/role=master -o jsonpath='{.items[*].status.addresses[?(@.type=="ExternalIP")].address}')
cat <<EOT >> $HOME/.ssh/config
Host master
    HostName $MASTER_IP
    User admin
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
EOT

ssh -T master "mkdir efs"
sleep 2
ssh -T master "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_DNS:/ efs"
sleep 4
PVC_NAME=$(kubectl get pvc efs-networks -o jsonpath='{.spec.volumeName}')
KNOW_NET_DIR="efs/efs-networks-${PVC_NAME}/"
sleep 2
echo "copying knowledge network to $KNOW_NET_DIR"
ssh -T master "aws s3 cp --quiet s3://KnowNets/KN-20rep-1706/userKN-20rep-1706.tgz - | sudo tar -xzC ${KNOW_NET_DIR} --strip 1"

curl https://storage.googleapis.com/kubernetes-helm/helm-v2.8.0-linux-amd64.tar.gz | tar xvz && \
  sudo mv linux-amd64/helm /usr/local/bin && \
  sudo rm -rf linux-amd64
if [ $? -eq 0 ]
  then
    echo "helm installed"
  else
    echo "help installation failed; exiting"
    exit
fi

kubectl --namespace kube-system create sa tiller && \
  kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller && \
  helm init --service-account tiller && \
  kubectl --namespace=kube-system patch deployment tiller-deploy --type=json \
    --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'
if [ $? -eq 0 ]
  then
    echo "tiller configured"
  else
    echo "tiller configuration failed; exiting"
    exit
fi

kubectl rollout status --namespace=kube-system deployment/tiller-deploy --watch
if [ $? -eq 0 ]
  then
    echo "tiller started"
  else
    echo "tiller startup failed; exiting"
    exit
fi

KUBEADM_COMMIT=ee6701690ee6bcef59f531cb9a65e71e84e712a9
sudo apt install -qq unzip && \
  curl -sSL -o kubeadm-bootstrap.zip https://github.com/nds-org/kubeadm-bootstrap/archive/$KUBEADM_COMMIT.zip && \
  unzip kubeadm-bootstrap.zip && \
  rm -rf kubeadm-bootstrap.zip && \
  mv kubeadm-bootstrap-$KUBEADM_COMMIT kubeadm-bootstrap && \
  cd kubeadm-bootstrap/support && \
  helm dependency build && \
  cd .. && \
  helm install --name=support --namespace=default support/ && \
  cd ..
if [ $? -eq 0 ]
  then
    echo "kubeadm started"
  else
    echo "kubeadm startup failed; exiting"
    exit
fi

# PRAMOD SAYS: Store the keys in encrypted S3 bucket and automate the transfer via S3 CLI
kubectl create secret tls knowssl-secret --key $SSL_KEY_PATH --cert $SSL_CRT_PATH && \
  curl -sSL https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/dev/knowengres.yaml | \
  sed -e "s/SERVER_DNS_NAME/$SERVER_DNS_NAME/" | \
  kubectl apply -f -
if [ $? -eq 0 ]
  then
    echo "ingress created"
  else
    echo "ingress creation failed; exiting"
    exit
fi

# note: leaving nest.dev.yaml on disk here so it can be edited and reapplied as needed
curl -sSL https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/dev/nest.dev.yaml | \
  sed -e "s/SERVER_DNS_NAME/$SERVER_DNS_NAME/" > nest.dev.yaml && \
  kubectl apply -f nest.dev.yaml && \
  kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/nest.rbac.yaml
if [ $? -eq 0 ]
  then
    echo "nest deployed"
  else
    echo "nest deploy failed; exiting"
    exit
fi

WEB_SG_INFO=$(aws ec2 create-security-group \
  --group-name "public-web-for-${SERVER_DNS_NAME}-$(date +%F)" \
  --description "public HTTP/HTTPS traffic for $SERVER_DNS_NAME" \
  --vpc-id $EFS_VPC_ID \
  --region $REGION)
if [ $? -eq 0 ]
  then
    echo "public HTTP/HTTPS security group created"
  else
    echo "public HTTP/HTTPS security group creation failed; exiting"
    exit
fi

WEB_SG_ID=$(echo $WEB_SG_INFO | sed -e "s/^.*: \"//" -e "s/\".*$//")
aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SG_ID \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region $REGION && \
aws ec2 authorize-security-group-ingress \
    --group-id $WEB_SG_ID \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region $REGION
if [ $? -eq 0 ]
  then
    echo "public HTTP/HTTPS security group configured"
  else
    echo "public HTTP/HTTPS security group configuration failed; exiting"
    exit
fi
    
aws ec2 modify-instance-attribute \
  --instance-id $DNS_NODE_ID \
  --groups $WEB_SG_ID $(aws ec2 describe-instances --instance-ids $DNS_NODE_ID --region $REGION --query "Reservations[0].Instances[0].SecurityGroups[*].GroupId" --output text) \
  --region $REGION
if [ $? -eq 0 ]
  then
    echo "public HTTP/HTTPS security group attached"
  else
    echo "public HTTP/HTTPS security group attachment failed; exiting"
    exit
fi

echo "
To enable cilogon, wait for database seeding to finish. Then edit nest.dev.yaml
in the current directory according to the instructions found within the file's
cilogon section. After saving changes, run
kubectl apply -f nest.dev.yaml
"

DNS_NODE_IP=$(aws ec2 describe-instances --instance-ids $DNS_NODE_ID --region $REGION --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "
Follow the instructions in the README for creating a DNS record, which should
point to IP address $DNS_NODE_IP."