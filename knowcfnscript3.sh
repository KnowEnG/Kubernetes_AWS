#!/bin/bash
exit_msg=" Sorry! Something went wrong. Please Delete the Stack and Try Again. "
divider_line="--------------------------------------------------------------------------"
echo

echo $divider_line
echo " Setting up KnowEnG-Platform K8S Cluster  | Roughly 25 mins "
echo " Go do something more productive instead of staring at the screen :) "
echo $divider_line
echo
sleep 2

echo $divider_line
echo " Installing kubectl "
echo $divider_line
sleep 2
sudo apt-get update && sudo apt-get install -y apt-transport-https && \
  curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add - && \
  echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee -a /etc/apt/sources.list.d/kubernetes.list && \
  sudo apt-get update && \
  sudo apt-get install -y kubectl
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
echo " Configuring kubectl "
echo $divider_line
echo
sleep 2
echo 'export KUBECONFIG=/home/ubuntu/kubeconfig' | sudo tee -a /etc/environment >> /dev/null
. /etc/environment
scp master:/home/ubuntu/kubeconfig .
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

echo $divider_line
echo " EFS Provisioner "
echo $divider_line
sleep 2
kubectl apply -f efs-provisioner.yaml
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
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/networks.pvc.yaml
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
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/postgres.pvc.yaml
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
echo " PVCs - redis"
echo $divider_line
sleep 2
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/redis.pvc.yaml
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- redis pvc created "
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
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/userfiles.pvc.yaml
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
echo " Seeding KnowNet | Takes about 5-10 minutes "
echo $divider_line
sleep 2
ssh -T master "sudo mkdir efs"
sleep 2
ssh -T master "sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,noresvport $EFS_DNS:/ efs"
sleep 4
PVC_NAME=$(kubectl get pvc efs-networks -o jsonpath='{.spec.volumeName}')
KNOW_NET_DIR="efs/efs-networks-${PVC_NAME}/"
sleep 2
echo "KNOW_NET_DIR: $KNOW_NET_DIR"
ssh -T master "sudo aws s3 cp --recursive s3://KnowNets/KN-20rep-1706/userKN-20rep-1706/ ${KNOW_NET_DIR}"
if [ $? -eq 0 ]
	then
	echo
	echo " Success-- KnowNet seeded "
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
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/nest.rbac.yaml
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
kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/nest.cfn.yaml
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
echo " Getting things Ready | Takes about 20 mins. Go play with your cat :) "
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
echo " Printing Load Balancer "
echo $divider_line
sleep 2
kubectl --namespace=default describe service nest-public-lb | grep "LoadBalancer Ingress"
if [ $? -eq 0 ]
	then
	echo
	echo " Congratulations-- KnowEnG Platform IS READY TO ROLL. Happy KnowEnG "
	sleep 2
	echo
else
	echo $exit_msg
	exit
fi
