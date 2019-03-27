# Deploying the KnowEnG Platform to AWS via CloudFormation Template

These instructions assume you have an AWS account and that you are signed in to the AWS Console.

1. Create a cryptographic key pair in the desired AWS region by following the instructions
for [Creating a Key Pair Using Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair).
(You can skip this step if you'd like to use a key pair you have already created in the region.)
Note you must select the region before creating the key pair; you can do that with the
dropdown menu that appears near the top-right corner of the screen.

   ![Dropdown to change region](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/1-change_region.png)


2. Launch the KnowEnG Platform's CloudFormation Template by clicking [here](https://console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/new?stackName=KnowEnG-Platform&templateURL=https://s3.amazonaws.com/knowscripts/knoweng-platform-simple.template).
You will then configure the template in a series of screens:

   1. On the first screen, change the region using the dropdown menu that appears
      near the top-right corner of the screen so that it matches the region of your 
      key pair from step 1. Then press the `Next` button.

      ![Dropdown to change region](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/2a-change_region_and_next.png)

   2. On the second screen, set the following options:

      1. **Stack name**: This is the name that will be used to identify the deployment
         in the AWS CloudFormation web interface. You might want to change the default value
         if you have multiple KnowEnG Platform deployments.

      2. **Availability Zone**: This is the AWS Availability Zone within your selected region
         that will host the cluster. Select any option from the list.

      3. **Admin Ingress Location**: This field can be used to limit administrator access
         to the cluster. If all of your administrator traffic will originate from a limited
         IP address range, you can enter it here. Otherwise, you can enter `0.0.0.0/0` to allow
         administrator traffic from all locations.

      4. **SSH Key**: Select the key pair from step 1.

      5. **Node Capacity**: This is the number of compute nodes that will be created within your cluster.
         We recommend the default value unless you plan to run many simultaneous jobs and wish
         to have them execute in parallel.

      6. **Instance Type**: This is the AWS EC2 instance type that will be used for each
         compute node. We recommend the default value unless you'll be analyzing spreadsheets
         that are larger than 1 gigabyte.

         Once you have set the above options, press the `Next` button.

   3. On the third screen, you can skip all of the options (`Tags`, `Permissions`, `Rollback Triggers`, 
      and `Advanced`). Press the `Next` button.

   4. On the fourth screen, review your settings. In the section labeled `Capabilities`, click 
      each of the checkboxes. Finally, press the `Create` button.
  
      After pressing the `Create` button, you will see a table of CloudFormation stacks.
      One stack in the table will have the name you set in step 2.ii.a.; that is the stack
      you just created. (You will also see a second stack appear with a similar name. 
      The second stack will be labeled `NESTED` and is created automatically as part of
      the KnowEnG Platform deployment process.) Refresh the table until the status for your new stack is
      `CREATE_COMPLETE`. This might take 10 minutes or so.

3. Gather details from new stack. These details will be needed in later steps.

   1. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EC2`
      from the `Compute` section.
      
      ![Dropdown to select EC2](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/3a-open_ec2.png)

   2. Click on `Running Instances`.
   
      ![Link to Running Instances](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/3b-open_running_instances.png)
      
   3. In the table of running instances, find the row with a `Name` of `bastion-host`. (If you have
      multiple instances with that name due to earlier deployments, choose the one whose `Launch Time` 
      matches the time you ran step 2. You might have to scroll your window to the right in order to see 
      the `Launch Time` column in the table.) Click on the `bastion-host` row in the table to display 
      instance details at the bottom of the screen. From the instance details, make a note of the 
      `IPv4 Public IP`.
   
      ![Details for bastion-host](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/3c-get_bastion_details.png)

   4. Deselect the row for `bastion-host` by clicking it again. Now find the row with a `Name` of
      `k8s-master`. (Once again, if you have multiple instances with that name, choose the one whose 
      `Launch Time` matches the time you ran step 2.) Click on the `k8s-master` row in the table to display 
      the instance details at the bottom of the screen. From the instance details, make a note of the
      `Security Groups` (there will only be one), the `Private IPs` (there will only be one), and the `VPC ID`.

      ![Details for k8s-master](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/3d-get_master_details.png)
    
4. Create storage for the KnowEnG Platform.

   1. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EFS`
      from the `Storage` section.
      
      ![Dropdown to select EFS](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/4a-open_efs.png)

   2. Press the `Create file system` button.
   
   3. On the first form, change the value of the **VPC** field so that it matches the `VPC ID` you
      captured in step 3.iv. (Note that each option for **VPC** will be of the form `{VPC ID} - {VPC name}`.
      You can ignore the `VPC name` portion of each option; i.e., just match the `VPC ID` portion from
      step 3.iv.) Then find the `Security groups` column in the table below, where you will see a value
      has already been entered. Click the `x` icon near the top-right corner of that pre-entered value to
      remove it. Then click in the now-empty field to add a new security group. From the list of options
      displayed, select the one that matches the value you found in `Security Groups` in step 3.iv. (Note 
      that each option will be of the form `{SG ID} - {SG name}`. You can ignore the `SG ID` portion of 
      each option; i.e., just match the `SG name` portion to the value from step 3.iv. Security group 
      names can be very similar to one another, so check carefully.) Press the `Next Step` button.
   
      ![First form to configure EFS](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/4c-configure_efs.png)

   4. On the second form, give a name to the new file system (e.g., `knoweng-platform-cloudformation`).           This name is only to help you identify the file system in the AWS Console. After entering the name,         scroll to the bottom of the page, skipping the other fields, and press the `Next Step` button.

      ![Second form to name EFS](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/4d-name_efs.png)

   5. On the following page, review your selections and press the `Create File System` button. When you
      are redirected to a page with a success message, make a note of the `DNS name` of your new file  
      system.

      ![EFS success page with DNS name](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/img/4e-get_efs_dns.png)

5. Complete deployment on the bastion virtual machine. These steps will be completed from the command
   line, not the AWS Console.

   1. Copy your key pair file from step 1 to `bastion-host`. If your local machine has
      a unix-like command line, the command will be
  
      ```
      scp -i {path/to/keypair} {path/to/keypair} ubuntu@{BASTION_PUBLIC_IP}:/home/ubuntu/.ssh/
      ```
  
      where `{path/to/keypair}` is the local path to your key pair file, and `{BASTION_PUBLIC_IP}`
      is the address found in step 3.iii. When asked to confirm the ECDSA key fingerprint, enter `yes`.
      (If you didn't do it in step 1, you will first need to set
      the permissions on your local copy of the key pair file using `chmod 400 {path/to/keypair}`.)
  
   2. SSH to `bastion-host`. If your local machine has a unix-like command line, the command
      will be
  
      ```
      ssh -i {path/to/keypair} ubuntu@{BASTION_PUBLIC_IP}
      ```
  
      where `{path/to/keypair}` is the local path to your key pair file, and `{BASTION_PUBLIC_IP}`
      is the address found in step 3.iii.
  
   3. In your SSH session on `bastion-host`, edit /home/ubuntu/.ssh/config to include the following block:

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
   
      where `{MASTER_PRIVATE_IP}` is the address you found in step 3.iv and `{keypair}` is
      the name of your key pair file that you copied to the `/home/ubuntu/.ssh/` directory in step 5.i.

    4. In your SSH session on `bastion-host`, run the following command, where `{EFS_DNS_NAME}`
       is the name from step 4.v.

       ```
       export EFS_DNS={EFS_DNS_NAME}
       ```

    5. Initialize the KnowEnG Platform. In your SSH session on `bastion-host`, run 
       the following two commands:
   
       ```
       wget https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/knowcfnscript3.sh
       sh knowcfnscript3.sh
       ```
   
       The script will take 40 minutes or so to complete. Upon successful completion, the 
       script will print a URL to open in your web browser.
   
    6. Open the KnowEnG Platform interface. In the web browser on your local machine, open 
       the URL printed at the end of step 5.v. Sign in with username `fakeuser` and password
       `GARBAGESECRET`.

# Deleting a KnowEnG Platform Deployment

1. In your SSH session on `bastion-host`, run `ssh master` and then `kubectl delete svc nest-public-lb`.

2. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EFS`
   from the `Storage` section. In the table of file systems, select the one you created in step 4.
   Press the `Actions` button above the table and select `Delete file system`. Follow the on-screen     
   instructions to confirm and complete the deletion.

3. In the AWS Console, open the `Services` dropdown near the top-left corner and select
   `CloudFormation` from the `Management & Governance` section. In the table of stacks, 
   find and select the one you created in step 2. (Note there will be a similarly-named stack labeled 
   `NESTED`. Do not delete the `NESTED` stack. It will be deleted automatically when you
   delete the stack you created in step 2.) Press the `Actions` button above the table
   and select `Delete Stack`. Follow the on-screen instructions to confirm and 
   complete the deletion. You will see the stack's status change to `DELETE_IN_PROGRESS`.
   Refresh the page until the stack no longer appears in the table, which might take 10 
   minutes or so.