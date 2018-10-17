
## Zero-To-KnowDev ([https://dev.knoweng.org](https://dev.knoweng.org))

### Overview
    * Steps 1-10 are to set up the **controller**
    * Steps 10-28? are to set up the **cluster**
    * Some text [To Clean the Resources](#danger-zone-to-clean-the-resources)
    * Some text [Using Private Docker Images?](#using-private-docker-images)

### Steps

1. Spin up kubectl cli host **KnowDevKOPS** (t2.medium) on AWS & create/edit security group **knowdevkops** to allow ssh (port 22) from your ip.

    Note: You will be given option to either use already created/downloaded key-pair or create a new one for this instance. If you use the existing one, you need to acknowledge you have it accessible/available.

    Optional: Record/copy the public ip given to the instance and update the record for "knowdevkops.knoweng.org" in the IPAM management console. But you can easily connect to this machine via it's public ip.

2. **Pramod!** Add steps to create **IAM Role KnowKubeKOPS** with permissions required for KOPS

3. Attach to the KnowDevKOPS the **IAM Role:KnowKubeKOPS** with following permissions:

    AmazonEC2FullAccess  
    AmazonS3FullAccess  
    IAMFullAccess  
    AmazonVPCFullAccess  
    AmazonElasticFileSystemFullAccess  

4.  SSH into the instance using the ssh key used/created while spinning up the instance.

    `ssh -i <ssh-key>.pem ubuntu@{ip/fqdn}`

    `sudo apt update && sudo apt upgrade -y && sudo apt dist-upgrade -y`

5.  Install the CLI tool **kops**:

    <pre>
    wget -O kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64 && \
      chmod +x ./kops && \
      sudo mv ./kops /usr/local/bin/
    </pre>

6. Install the CLI tool **kubectl**:

    <pre>
    wget -O kubectl https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl && \
      chmod +x ./kubectl && \
      sudo mv ./kubectl /usr/local/bin/kubectl
    </pre>

7. Install the **AWS CLI** tools:

    <pre>
    sudo apt install python3-pip -y && \
      pip3 install --upgrade pip && \
      pip install awscli --upgrade --user
    </pre>

8. Cluster State storage - create a dedicated S3 bucket for kops to use:

    Note: S3 requires `--create-bucket-configuration LocationConstraint=<region>` for regions other than `us-east-1`.

    <pre>
    aws s3api create-bucket \
      --bucket knowdevkops-state-store \
      --region us-east-1
    </pre>

9. KOPS strongly recommends versioning the S3 bucket:

    `aws s3api put-bucket-versioning --bucket knowdevkops-state-store  --versioning-configuration Status=Enabled`

10. Set up an ssh keypair to use with the cluster:

    `ssh-keygen -t rsa -b 4096 -N '' -f "$HOME/.ssh/id_rsa" -q`

11. Set up a few environment variables for the cluster "KnowDev":

    <pre>
    export NAME=knowdev.k8s.local && \
      export KOPS_STATE_STORE=s3://knowdevkops-state-store && \
      export REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'` && \
      export ZONES=$(aws ec2 describe-availability-zones --region $REGION | grep ZoneName | awk '{print $2}' | tr -d '"') && \
      export ZONES=$(echo $ZONES | tr -d " " | rev | cut -c 2- | rev)
    </pre>

12. Create the cluster:

    Note: [masters will not boot on M5 and C5 instance types](https://github.com/kubernetes/kops/blob/master/docs/releases/1.8-NOTES.md#significant-changes) but may have changed.

    <**Pramod!** Consider using Kubernetes version with flag: `--kubernetes-version` and consider using `--vpc: string Set to use a shared VPC` and [many other KOPS flags](https://github.com/kubernetes/kops/blob/master/docs/cli/kops_create_cluster.md) for helm & cfn setup>

    <pre>
    kops create cluster $NAME \
      --zones $ZONES \
      --authorization RBAC \
      --master-size c4.large \
      --master-volume-size 100 \
      --node-size c4.xlarge \
      --node-volume-size 50 \
      --node-count 1 \
      --yes
    </pre>

13. Autoscaler:

    **pipes1**: on-demand worker node for running compute jobs before auto-scaling  
    **pipes2**: ASG for running compute jobs when scaling up (0-5 nodes)  

    `kops create ig pipes1`

    Change the following:

      * the machineType
      * maxSize
      * minSize
      * nodeLabels.instancegroup
      * nodeLabels.pipeline_jobs (add)

    <pre>
    spec:
      image: kope.io/k8s-1.9-debian-jessie-amd64-hvm-ebs-2018-03-11
      machineType: c4.xlarge
      maxSize: 1
      minSize: 1
      nodeLabels:
        kops.k8s.io/instancegroup: pipes1
        pipelines_jobs: "true"
      role: Node
    </pre>

    `kops create ig pipes2`

    Change the following:

      * the machineType
      * maxSize
      * minSize
      * nodeLabels.instancegroup
      * nodeLabels.pipeline_jobs (add)

    <pre>
    spec:
      image: kope.io/k8s-1.9-debian-jessie-amd64-hvm-ebs-2018-03-11
      machineType: c4.8xlarge
      maxSize: 5
      minSize: 0
      nodeLabels:
        kops.k8s.io/instancegroup: pipes2
        pipelines_jobs: "true"
      role: Node
      taints:
      - dedicated=pipelines_jobs:NoSchedule
    </pre>

14. Provide KOPS with IAM permissions to be deployed to API server for Auto-scaling:

    `kops edit cluster $NAME`

    Add additionalPolicies all the way to the end with two spaces indentation

    <pre>
    spec:
      ...
      ...
      additionalPolicies:
        node: |
          [
            {
                "Effect": "Allow",
                "Action": [
                    "autoscaling:DescribeAutoScalingGroups",
                    "autoscaling:DescribeAutoScalingInstances",
                    "autoscaling:DescribeTags",
                    "autoscaling:DescribeLaunchConfigurations",
                    "autoscaling:SetDesiredCapacity",
                    "autoscaling:TerminateInstanceInAutoScalingGroup",
                    "ec2:DescribeLaunchTemplateVersions"
                ],
                "Resource": "*"
            }
          ]
    </pre>

15. Update the cluster:

    `kops update cluster $NAME --yes`

16. Customize Autoscaler:

    `wget https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-one-asg.yaml`

    Note: In the Deployment section:

    **spec.spec.containers.image:version** ([autoscaler version that needs to be compatible with k8s version](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler#releases)) → should be v1.2.2 unless autoscaler upgraded, **spec.spec.containers.command.--nodes**, **spec.spec.containers.env.name**, **spec.spec.containers.env.value**

    <pre>
    spec:
      ...
	    ...
        spec:
          serviceAccountName: cluster-autoscaler
          containers:
            - image: k8s.gcr.io/cluster-autoscaler:v1.2.2
              ...
					    ...
              command:
                ...
						    ...
                - --nodes=0:5:pipes2.knowdev.k8s.local
              env:
                - name: AWS_REGION
                  value: us-east-1
              volumeMounts:
                ...
    </pre>

17. Deploy Autoscaler:

    `kubectl apply -f cluster-autoscaler-one-asg.yaml`

18. Configure an EFS on the same VPC and Security Group ("nodes.knowdev.k8s.local") as the new cluster: only change the efs vpc and security groups for now and transfer files to efs-network below....

    If the efs doesn't already exist:

      1. Go to [EFS via AWS Console](https://console.aws.amazon.com/efs/home?region=us-east-1#/filesystems)
      2. Click on "Create File System"
      3. Under "Configure file system access", Select the VPC created by the K8S cluster, i.e. add all subnets
      4. Under "Manage mount targets", Make sure the subnets and security groups correspond to the newly created ones as well.

    If the efs already exists that you can use for this cluster:

      1. Select the efs name > Manage file system access > Choose the cluster VPC (**vpc-<id> - knowdev.k8s.local**)
      2. Under "Manage mount targets":
          a. Add all subnets (**subnet-<id> - us-east-1<a-f>.knowdev.k8s.local**)
          b. Delete the default security group
          c. Attach the new security groups (**sg-<id> - nodes.knowdev.k8s.local**)
          d. Save

19. Deploy the efs provisioner

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/efs-provisioner-dev.yaml`

20. Deploy the efs rbac:

    `kubectl apply -f https://raw.githubusercontent.com/kubernetes-incubator/external-storage/master/aws/efs/deploy/rbac.yaml`

21. Allocate/Populate Shared Storage:

    Make sure the "Life Cycle State" under "Mount targets" in EFS is "Available" and NOT "Creating" before attaching a new instance for efs-access and creating following PVCs.

    **Clean the network files from old cluster before new cluster from within the efs-access instance (instructions below) and before creating following PVCs (if using existing efs). If not cleaned, it will create a new directory called "efs-*-pvc-" adding to the storage costs).**

    `cd efs/ → sudo rm -r efs-*`

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/networks.pvc.yaml`

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/postgres.pvc.yaml`

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/redis.pvc.yaml`

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/pvcs/userfiles.pvc.yaml`

22. Seed the KnowEnG database with the options to present to the user in the UI for the submitting a new pipeline job (In the efs-access instance and not KOPS instance)

    Dummy instance (efs-access) steps: First, create a security group knowdev-efs-access in the same new VPC created by the KnowDev and the one you attached to the EFS and NOT the default or other VPC: This SG should let you connect to the the knowdev-efs-access instance by opening up port 22 from your ip, and that's all you need → Create a new instance knowdev-efs-access (any size, tiny is fine) in the same VPC, otherwise, you won't be able to access efs and/or the new SG → During Step 3: Configure Instance Details, When you change network field to the new VPC and not default -> the Auto-assign Public IP value changes to Use subnet setting (Disable), change that to Enable so the instance has public ip to ssh into → During Step 6: Configure Security Group's Assign a security group, choose Select an existing security group, and check knowdev-efs-access & nodes.knowdev.k8s.local → Attach Use a new or already existing key-pair while launching and to connect later → Connect to the instance and follow the mounting instruction on EFS console (apt update, install nfs-client, mkdir efs, and mount .... ) →

    Copying the network files for a new cluster: cd efs/ → create the pvcs below and make sure efs-network-someuuid now appears → sudo cp network-files-to-copy(?)/. efs-network-someuuid/ → efs-network-someuuid now should have the network files that's in in the originals folder. → When you deploy nest.prod.yaml, these files would let the nest pods and jobs container run successfully.

    Alternatively, copy from the s3 bucket (need to attach IAM KnowKubeDevKOPS to this knowdev-efs-access instance and install aws cli tool as "root"):

    `sudo -s`

    `root@<private-ip>:~# apt install awscli -y`

    `aws s3 cp --recursive s3://KnowNets/KN-20rep-1706/userKN-20rep-1706/ efs/{efs-network-*}/`

    Important: This dummy instance will prevent KOPS delete cluster, so to clean resources before deleting cluster: detach the sg nodes.knowdev.k8s.local → detach and delete knowdev-efs-access → terminate the instance

    Note: While the files are being copied, you can perform the following operations as per the instructions below up to and not including "Deploy KnowEnG Platform", i.e. :

      1. Choose one of your worker nodes and label it with "has-dns=true"
      2. Helm install nginx-controller
      3. Install nginx and other support stuff!

23. Choose one of your worker nodes and label it with "has-dns=true"

    `kubectl label node $(kubectl get nodes -l kops.k8s.io/instancegroup=nodes --no-headers | head -n 1 | awk '{print $1}') has-dns=true`

    Create a new security group **knowdevweb** in cluster VPC that opens up ports **80** & **443** to the world. Attach this sg to the node that has been labelled **has-dns=true**.

    Update the DNS record for dev.knoweng.org to point to the ip of this node

24. Helm install nginx-controller

    <pre>
    curl https://storage.googleapis.com/kubernetes-helm/helm-v2.8.0-linux-amd64.tar.gz | tar xvz && \
      sudo mv linux-amd64/helm /usr/local/bin && \
      sudo rm -rf linux-amd64
    </pre>

    `kubectl --namespace kube-system create sa tiller`

    `kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller`

    `helm init --service-account tiller`

    `kubectl --namespace=kube-system patch deployment tiller-deploy --type=json --patch='[{"op": "add", "path": "/spec/template/spec/containers/0/command", "value": ["/tiller", "--listen=localhost:44134"]}]'`

    Optional: Wait for tiller to be ready!

    `kubectl rollout status --namespace=kube-system deployment/tiller-deploy --watch`

25. Install nginx and other support stuff!

    `git clone https://github.com/nds-org/kubeadm-bootstrap.git`

    `cd kubeadm-bootstrap/`

    `cd support && helm dep up && cd ..`

    `helm install --name=support --namespace=support support/`

    `cd ..`

26. SSL Setup:

    **Pramod!** Store the keys in encrypted S3 bucket and automate the transfer via S3 CLI

    \# Copy the SSL certificate & Key to the KnowDevKOPS instance from a source (such as your local machine):

    \# Run this NOT in KnowDevKOPS (but in a machine which can access the path/to/ssl-certs):

    `scp -i <ssh-key>.pem path/to/knoweng.key ubuntu@<knowdevkops>:/home/ubuntu/`

    `scp -i <ssh-key>.pem path/to/knoweng.crt ubuntu@<knowdevkops>:/home/ubuntu/`

    \# Create the **knowssl-secret**:

    `kubectl create secret tls knowdevssl-secret --key /home/ubuntu/knoweng.key --cert /home/ubuntu/knoweng.crt`

    \# Create **Ingress Object** & **TLS Ingress Rule**:

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/knowengressdev.yaml`

27. Deploy KnowEnG Platform (after efs-network files copying is complete):

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/nest.dev.yaml`

    `kubectl apply -f https://raw.githubusercontent.com/prkriz/knowkubedev/master/nest.rbac.yaml`

28. Stop KnowDevKOPS until further use and detach/modify security group for no ssh access


## DANGER ZONE! To Clean the Resources:

Make sure the efs is detached from all the security groups and make sure efs doesn't belong to any VPC anymore.

Also the new security group"knowdevweb" opening up web ports to "node" should be de-tached from node and deleted.

Also, clean the resources associated with Dummy efs-access instance (see efs docs above).

`helm delete support --purge`

`kubectl delete namespace support`

`export NAME=knowdev.k8s.local && export KOPS_STATE_STORE=s3://knowdevkops-state-store`

`kops delete cluster $NAME --yes`

Note: This may take a while. Verify via Console/CLI that the KnowDev master(s), node(s), pipes1(s), and pipes2(s) are terminated.

Finally, remove A record for "dev.knoweng.org" in the IPAM manager, so that UIUC owned domain doesn't point to an arbitrary machine.


## Using Private Docker Images?

The "nest-private" images currently defined in the knoweng_startup/platform/nest.yaml file are **private Docker images**, as they may contain unscrubbed secrets.

First, you will need to request access to this Docker repository, or build and push the images yourself to your own **private Docker repository**.

NOTE: you are allowed one private Docker repository for free on [https://hub.docker.com](https://hub.docker.com).

You can embed your Docker credentials into a kubernetes secret by running the following:

`kubectl create secret docker-registry regcred --docker-server=<your-registry-server> --docker-username=<your-name> --docker-password=<your-pword> --docker-email=<your-email>`

