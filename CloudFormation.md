# Deploying the KnowEnG Platform to AWS via CloudFormation Template

1. Create a cryptographic key pair in the desired AWS region by following the instructions
for [Creating a Key Pair Using Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair).
(You can skip this step if you'd like to use a key pair you have already created in the region.)
Note you must select the region before creating the key pair; you can do that with the
dropdown menu that appears near the top-right corner of the screen.

FIXME IMAGE
1-change_region.png

2. Launch the KnowEnG Platform's CloudFormation Template by clicking [here](https://console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/new?stackName=KnowEnG-Platform&templateURL=https://s3.amazonaws.com/knowscripts/knoweng-platform-simple.template)
You will then configure the template in a series of screens:

  A. On the first screen, change the region using the dropdown menu that appears
  near the top-right corner of the screen so that it matches the region of your 
  key pair from step 1. Then press the `Next` button.

  FIXME IMAGE
  2a-change_region_and_next.png

  B. On the second screen, set the following options:

    i. **Stack name**: This is the name that will be used to identify the deployment
    in the AWS CloudFormation web interface. You might want to change the default value
    if you have multiple KnowEnG Platform deployments.

    ii. **Availability Zone**: This is the AWS Availability Zone within your selected region
    that will host the cluster. Select any option from the list.

    iii. **Admin Ingress Location**: This field can be used to limit administrator access
    to the cluster. If all of your administrator traffic will originate from a limited
    IP address range, you can enter it here. Otherwise, you can enter `0.0.0.0/0` to allow
    administrator traffic from all locations.

    iv. **SSH Key**: Select the key pair from step 1.

    v. **Node Capacity**: This is the number of compute nodes that will be created within your cluster.
    We recommend the default value unless you plan to run many simultaneous jobs and wish
    to have them execute in parallel.

    vi. **Instance Type**: This is the AWS EC2 instance type that will be used for each
    compute node. We recommend the default value unless you'll be analyzing spreadsheets
    that are larger than 1 gigabyte.

  Once you have set the above options, press the `Next` button.

  C. On the third screen, you can skip all of the options (`Tags`, `Permissions`, `Rollback Triggers`, 
and `Advanced`). Press the `Next` button.

  D. On the fourth screen, review your settings. In the section labeled `Capabilities`, click 
  each of the checkboxes. Finally, press the `Create` button.
  
After pressing the `Create` button, you will see a table of CloudFormation stacks.
One stack in the table will have the name you set in step 2.B.i.; that is the stack
you just created. Refresh the table until the status for your new stack is
`CREATE_COMPLETE`. (You will also see a second stack appear with a similar name. 
The second stack will be labeled `NESTED` and is created automatically as part of
the KnowEnG Platform deployment process.) This might take 10 minutes or so.

3. Gather details from new stack.

switch to EC2 in Compute
FIXME image
3a-open_ec2.png

click Running Instances
FIXME image
3b-open_running_instances.png

select bastion-host and grab public IP
FIXME image
3c-get_bastion_details.png

deselect bastion-host; select k8s-master and grab private IP, vpc, and sec group
FIXME image
3d-get_master_details.png


in my case,
bastion public ip = 54.187.226.60
master private ip = 10.0.12.220
master vpc = vpc-04a10f4cafaef2be8
master sg = KnowEnG-Platform-mjb-K8sStack-J73OHZWFHE1S-ClusterSecGroup-193IE7YGN0NT6



Your new stack will include one virtual machine named `bastion-host`. This is the 
machine you will use to complete the deployment.

  A. Determine the public address of `bastion-host`.
  
    i. In the table of CloudFormation stacks from step 2, find your new stack and
    click on its name in the `Stack Name` column. This will display more detailed
    information about the stack.
    
    ii. Scroll down to a section header for `Resources`, and click on the section 
    header to expand the section. This will reveal a table of resources.
    
    iii. Find the row in the table with a `Logical ID` of `bastion-host`, and click 
    on its `Physical ID`. This will open a new browser tab showing more information
    about `bastion-host`.
    
    iv. Find the `Public DNS (IPv4)` near the bottom-right corner of the screen.
    Copy the value to your clipboard. These instructions will refer to the value as
    `BASTION_PUBLIC_IP`.
    
    FIXME MASTER_PRIVATE_IP
    
4. Create storage.


switch to EFS
FIXME image
4a-open_efs.png

press `Create file system` button

on first form, select master VPC as VPC (you'll see vpcid - vpc name)
in table, Security groups column, click x button to remove default security group
click in empty SC cell to select master SG (note options will be formatted as sgid-sgname, but we previously noted only sgname; look for match on sgname; note names very similar, so check carefully
FIXME image
4b-configure_efs.png

press `Next Step`

add Name tag
FIXME image
4c-name_efs.png

scroll to bottom of page, skipping others, and press `Next Step`

press `Create File System`

on success page, capture DNS name
FIXME image
4d-get_efs_dns.png
mine = fs-88637520.efs.us-west-2.amazonaws.com

5. Complete deployment on the bastion virtual machine.

  A. Copy your key pair file from step 1 to `bastion-host`. If your local machine has
  a unix-like command line, the command will be
  
  ```
  scp -i {path/to/keypair} {path/to/keypair} ubuntu@{BASTION_PUBLIC_IP}:/home/ubuntu/.ssh/
  ```
  
  where `{path/to/keypair}` is the local path to your key pair file, and `{BASTION_PUBLIC_IP}`
  is the address found in step 3.A. When asked to confirm the ECDSA key fingerprint, enter yes.
  (If you didn't do it in step 1, you will first need to set
  the permissions on your local copy of the key pair file using `chmod 400 {path/to/keypair}`.)
  
  B. SSH to `bastion-host`. If your local machine has a unix-like command line, the command
  will be
  
  ```
  ssh -i {path/to/keypair} ubuntu@{BASTION_PUBLIC_IP}
  ```
  
  where `{path/to/keypair}` is the local path to your key pair file, and `{BASTION_PUBLIC_IP}`
  is the address found in step 3.A.
  
  C. In your SSH session on `bastion-host`, edit /home/ubuntu/.ssh/config to include the following block:

   ```
   Host master
       HostName {MASTER_PRIVATE_IP}
       Port 22
       User ubuntu
       IdentityFile /home/ubuntu/.ssh/{keypair}
       StrictHostKeyChecking no
       UserKnownHostsFile /dev/null
       ServerAliveInterval 60
   ```
   
   where `{MASTER_PRIVATE_IP}` is the address you found in step 3.A and `{keypair}` is
   the name of your key pair file that you copied to the `/home/ubuntu/.ssh/` directory in step 5.A.

   D. In your SSH session on `bastion-host`, run the following command, where `{EFS_DNS_NAME}`
   is the name from step 4.

   ```
   export EFS_DNS={EFS_DNS_NAME}
   ```
   
   

   F. Initialize the KnowEnG Platform. In your SSH session on `bastion-host`, run 
   the following two commands:
   
   ```
   wget https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/knowcfnscript3.sh
   sh knowcfnscript3.sh
   ```
   
   The script will take 40 minutes or so to complete. Upon successful completion, the 
   script will print a URL to open in your web browser.
   
   G. Open the KnowEnG Platform interface. In the web browser on your local machine, open 
      the URL printed at the end of step 5.f. Sign in with username `fakeuser` and password
      `GARBAGESECRET`.

# Deleting a KnowEnG Platform Deployment

FIXME ssh to master first?
1. In your SSH session on `bastion-host`, run `kubectl delete svc nest-public-lb`.
   ssh master
   kubectl...

2. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EFS`
   from the `Storage` section. In the table of file systems, select the one you created in step 4.
   Press the `Actions` button above the table and select `Delete file system`. Follow the on-screen instructions
   to confirm and complete the deletion.

3. In the AWS Console, open the `Services` dropdown near the top-left corner and select
   `CloudFormation` from the `Management & Governance` section. In the table of stacks, 
   find and select the one you created in step 2. (Note there will be a similarly-named stack labeled 
   `NESTED`. Do not delete the `NESTED` stack. It will be deleted automatically when you
   delete the stack you created in step 2.) Press the `Actions` button above the table
   and select `Delete Stack`. Follow the on-screen instructions to confirm and 
   complete the deletion. You will see the stack's status change to `DELETE_IN_PROGRESS`.
   Refresh the page until the stack no longer appears in the table, which might take 10 or so
   minutes.

(It has happened sometimes that this delete fails because a VPC could
not be deleted; in those cases, deleting the VPC from the AWS console --
make sure you delete the right VPC! -- and then re-trying to delete
the stack has worked.)
