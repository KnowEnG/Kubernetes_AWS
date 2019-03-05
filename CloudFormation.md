# knowkubedev
Kubernetes Deployment files to setup KnowKubeDev (KnowEng Platform Dev Cluster)

# To launch CFN:

## Create a ssh key-pair in a desired region
# [Launch CFN](https://us-west-2.console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/new?stackName=KnowEnG-Platform&templateURL=https://s3.amazonaws.com/knowscripts/knoweng-platform-with-new-vpc.template) in the desired region. Takes about 10 minutes

CFN template URL: https://s3.amazonaws.com/knowscripts/knoweng-platform-with-new-vpc.template

Also available here: https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/knoweng-platform-with-new-vpc.template

# Local- move keypair to bastion from local
`scp -i {path/to/keypair}.pem {path/to/keypair}.pem ubuntu@{BASTION_IP}:/home/ubuntu/.ssh/`

# Bastion- contents of $HOME/.ssh/config
```
Host master
    HostName {MASTER_PRIVATE_IP}
    Port 22
    User ubuntu
    IdentityFile ~/.ssh/{keypair}.pem
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    ServerAliveInterval 60
```

# AWS Console- Create EFS under master's VPC and cluster security group. Takes about 3 minutes

# Bastion- Export EFS
`export EFS_DNS={EFS_DNS_NAME}`

# Bastion- Modify efs id (file system id), availability zone (region), and efs server (server)
New location:
`wget https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/efs-provisioner.yaml`

Old location:
`wget https://raw.githubusercontent.com/prkriz/knowkubedev/master/efs-provisioner.yaml`

# Bastion- Run the KNOWENG_INIT_FILE
New steps:
```
wget https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/knowcfnscript3.sh
sh knowcfnscript3.sh
```

Old steps:
```
wget https://raw.githubusercontent.com/prkriz/knowkubedev/master/knowcfnscript3.sh
sh knowcfnscript3.sh
```

# Clean Resources/Stack

## Delete EFS mount targets and optionally, efs.

## Delete the load balancer exposed by kubectl
`kubectl delete svc nest-public-lb`

## Delete the non-nested stack from AWS Cloudformation Console
(It has happened sometimes that this delete fails because a VPC could
not be deleted; in those cases, deleting the VPC on the AWS console --
make sure you delete the right VPC! -- and then re-trying to delete
the stack has worked.)
