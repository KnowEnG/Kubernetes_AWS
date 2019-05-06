#!/bin/bash
exit_msg=" Sorry! Something went wrong. Please Delete the Stack and Try Again. "
divider_line="--------------------------------------------------------------------------"
echo

echo $divider_line
echo " Setting up KnowEnG-Platform K8S Cluster  | Roughly 40 min "
echo $divider_line
echo
sleep 2

echo $divider_line
echo " Installing kubectl "
echo $divider_line
sleep 2
sudo apt-get update && sudo apt-get install -y apt-transport-https && \
  curl -sSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update && \
  sudo apt-get install -qq kubectl
if [ $? -eq 0 ]
	then
	echo
	kubectl version
	echo " Success-- kubectl installed "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Installing awscli "
echo $divider_line
sleep 2
sudo apt-get -qq install awscli
if [ $? -eq 0 ]
	then
	echo " Success-- awscli installed "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Configuring connection to kubernetes master "
echo $divider_line
# 169.254.169.254 IP address below is link-local address for EC2 metadata

# get bastion instance id and private ip
BASTION_INSTANCE_ID=$(curl -sSL http://169.254.169.254/latest/meta-data/instance-id)
BASTION_PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

REGION=$(curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}')

# get cluster security group and k8s master private ip
CLUSTER_SG_ID=$(aws ec2 describe-security-groups \
  --region $REGION \
  --query "SecurityGroups[?IpPermissions[?IpRanges[?contains(@.CidrIp, '$BASTION_PRIVATE_IP') == \`true\`]]].GroupId" --output text)
MASTER_PRIVATE_IP=$(aws ec2 describe-instances \
  --region $REGION \
  --query "Reservations[].Instances[] | @[?SecurityGroups[?GroupId=='$CLUSTER_SG_ID']] | @[?Tags[?Value=='k8s-master']].PrivateIpAddress | [0]" \
  --output text)

# find the private key for connecting to k8s master
BASTION_PUBLIC_KEY=$(curl -sSL http://169.254.169.254/latest/meta-data/public-keys/0/openssh-key | cut -f2 -d ' ')
MASTER_KEY_FILE=''
for SSH_DIR_FILE in $(find $HOME/.ssh -type f -not -name "authorized_keys") ; do
  SSH_DIR_FILE_PUBLIC_KEY=$(ssh-keygen -q -y -f "$SSH_DIR_FILE")
  if [ $? -eq 0 ]
    SSH_DIR_FILE_PUBLIC_KEY=$(echo $SSH_DIR_FILE_PUBLIC_KEY | cut -f2 -d ' ')
    then
    if [ "$SSH_DIR_FILE_PUBLIC_KEY" = "$BASTION_PUBLIC_KEY" ]
      then
      MASTER_KEY_FILE=$SSH_DIR_FILE
    fi
  fi
done

if [ $MASTER_KEY_FILE = '' ]
	then
	echo "Could not find private key for master node."
	echo $exit_msg
	exit
fi

cat <<EOT >> $HOME/.ssh/config
Host master
    HostName $MASTER_PRIVATE_IP
    Port 22
    User ubuntu
    IdentityFile $MASTER_KEY_FILE
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
EOT

echo $divider_line
echo " Configuring kubectl "
echo $divider_line
echo
sleep 2
mkdir $HOME/.kube
scp master:/home/ubuntu/kubeconfig $HOME/.kube/config
if [ $? -eq 0 ]
	then
	echo
	kubectl version
	echo " Success-- kubectl Configured "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

# create an EFS for data shared among nodes
echo $divider_line
echo " Preparing storage "
echo $divider_line
echo
sleep 2
EFS_CREATION_DATA=$(aws efs create-file-system --creation-token $(uuidgen) --region $REGION)
if [ $? -eq 0 ]
	then
	echo
	kubectl version
	echo " Success-- storage prepared "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

# get the aws filesystem id for the new EFS 
EFS_ID=$(echo $EFS_CREATION_DATA | sed -e "s/^.*FileSystemId\": \"//" -e "s/\".*$//")

# wait for the EFS to become ready
while [ "available" != $(aws efs describe-file-systems --file-system-id $EFS_ID --region $REGION --query "FileSystems[0].LifeCycleState" --output text) ]; do
  echo "checking EFS again in 15 seconds (expect < 1 min for this step)"
  sleep 15s
done
echo "EFS ready"

# give the EFS a name
# NOTE: newer versions of awscli can set tags while creating the EFS
STACK_NAME=$(aws ec2 describe-security-groups \
    --region $REGION \
    --query "SecurityGroups[?GroupId=='$CLUSTER_SG_ID'].Tags[] | @[?Key=='KubernetesCluster'].Value" \
    --output text)
aws efs create-tags --file-system-id $EFS_ID --tags Key=Name,Value="$STACK_NAME" --region $REGION

# get the vpc id, security group id, and subnet ids we'll need to configure the
# EFS mount targets
EFS_VPC_ID=$(aws ec2 describe-instances --region $REGION --query "Reservations[].Instances[?PrivateIpAddress=='$MASTER_PRIVATE_IP'].NetworkInterfaces[0].VpcId" --output text)
EFS_SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters Name=vpc-id,Values=$EFS_VPC_ID \
  --region $REGION \
  --query "Subnets[?MapPublicIpOnLaunch==\`false\`].SubnetId" \
  --output text)

# create the mount targets
for EFS_SUBNET_ID in $EFS_SUBNET_IDS ; do
  aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $EFS_SUBNET_ID --security-groups $CLUSTER_SG_ID --region $REGION
done

# wait for the mount targets to become ready
while [ $(echo $EFS_SUBNET_IDS | wc -w) -ne $(aws efs describe-mount-targets --file-system-id $EFS_ID --region $REGION --query "length(MountTargets[?LifeCycleState=='available'])") ]; do
  echo "checking mount targets again in 15 seconds (expect ~3 min for this step)"
  sleep 15s
done
echo "mount targets ready"

# assemble the dns name of the EFS server (this formula comes from aws docs)
EFS_DNS=${EFS_ID}.efs.${REGION}.amazonaws.com

echo $divider_line
echo " EFS Provisioner "
echo $divider_line
sleep 2
curl -s https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/common/efs-provisioner.yaml | \
    sed -e "s/EFS_DNS/$EFS_DNS/" -e "s/EFS_ID/$EFS_ID/" -e "s/EFS_REGION/$REGION/" | \
    kubectl apply -f -
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- EFS provisioned "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " EFS RBAC "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/aws/efs/deploy/rbac.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- EFS RBAC applied "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " PVCs - networks "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/common/networks.pvc.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- networks pvc created "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " PVCs - postgres "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/postgres.pvc.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- postgres pvc created "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " PVCs - userfiles "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/common/userfiles.pvc.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- userfiles pvc created "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Copying Knowledge Network | Takes about 15 min "
echo $divider_line
sleep 2
ssh -T master "mkdir efs"
sleep 2
ssh -T master "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_DNS:/ efs"
sleep 4
PVC_NAME=''
while [ -z "$PVC_NAME" ]; do
  PVC_NAME=$(kubectl get pvc efs-networks -o jsonpath='{.spec.volumeName}')
  echo "waiting for PVC (expect < 1 min for this step)"
  sleep 5s
done
KNOW_NET_DIR="efs/efs-networks-${PVC_NAME}/"
sleep 2
echo "KNOW_NET_DIR: $KNOW_NET_DIR"
ssh -T master "aws s3 cp --quiet s3://KnowNets/KN-20rep-1706/userKN-20rep-1706.tgz - | sudo tar -xzC ${KNOW_NET_DIR} --strip 1"
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- Knowledge Network copied "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Pods RBAC "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/common/nest.rbac.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- pods RBAC applied "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Deploying KnowEnG pods "
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/cloudformation/nest.cfn.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- KnowEnG Pods Deployed "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Exposing Load Balancer "
echo $divider_line
sleep 4
kubectl expose --namespace=default deployment nest --type=LoadBalancer --port=80 --target-port=80 --name=nest-public-lb
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- Load Balancer Exposed "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Getting things Ready | Takes about 20 min "
echo $divider_line
i=20; while [ $i -gt 0 ]; do echo $i minute\(s\) remaining; i=`expr $i - 1`; sleep 60;  done
kubectl label nodes $(kubectl get nodes -o=custom-columns=NAME:.metadata.name,SPEC:.spec.taints | grep none | awk '{print $1}') pipelines_jobs=true
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- KnowEnG Platform is almost ready "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi

echo $divider_line
echo " Printing Platform URL "
echo $divider_line
sleep 2
LB_URL=$(kubectl --namespace=default describe service nest-public-lb | grep "LoadBalancer Ingress" | sed -e "s/^LoadBalancer Ingress:\s*/http:\/\//")
if [ $? -eq 0 ]
	then
	echo
	echo " Congratulations-- KnowEnG Platform is ready. "
	echo " Open $LB_URL in your browser. "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi
