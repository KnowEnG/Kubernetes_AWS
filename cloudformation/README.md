# Deploying the KnowEnG Platform to AWS via CloudFormation Template

These instructions assume you have an AWS account and that you are signed in to the AWS Console.

1. Create a cryptographic key pair in the desired AWS region by following the instructions
for [Creating a Key Pair Using Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html#having-ec2-create-your-key-pair).
(You can skip this step if you'd like to use a key pair you have already created in the region.)
Note you must select the region before creating the key pair; you can do that with the
dropdown menu that appears near the top-right corner of the screen.

   ![Dropdown to change region](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/1-change_region.png)


2. Launch the KnowEnG Platform's CloudFormation Template by clicking [here](https://console.aws.amazon.com/cloudformation/home?region=us-west-1#/stacks/new?stackName=KnowEnG-Platform&templateURL=https://s3.amazonaws.com/knowscripts/knoweng-platform-simple.template).
You will then configure the template in a series of screens:

   1. On the first screen, change the region using the dropdown menu that appears
      near the top-right corner of the screen so that it matches the region of your 
      key pair from step 1. Then press the `Next` button.

      ![Dropdown to change region](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/2a-change_region_and_next.png)

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
      Refresh the page, and you will see that one stack in the table has the name you set 
      in step 2.ii.a.; that is the stack you just created. (If you continue to refresh, you will 
      eventually see a second stack appear with a similar name.  The second stack will be labeled 
      `NESTED` and is created automatically as part of the KnowEnG Platform deployment process.) 
      Refresh the table until the status for your new stack is `CREATE_COMPLETE`. This might take 
      10 minutes or so.

3. Find the bastion IP address from new stack. This IP address will be needed in later steps.

   1. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EC2`
      from the `Compute` section.
      
      ![Dropdown to select EC2](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/3a-open_ec2.png)

   2. Click on `Running Instances`.
   
      ![Link to Running Instances](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/3b-open_running_instances.png)
      
   3. In the table of running instances, find the row with a `Name` of `bastion-host`. (If you have
      multiple instances with that name due to earlier deployments, choose the one whose `Launch Time` 
      matches the time you ran step 2. You might have to scroll your window to the right in order to see 
      the `Launch Time` column in the table.) Click on the `bastion-host` row in the table to display 
      instance details at the bottom of the screen. From the instance details, make a note of the 
      `IPv4 Public IP`.
   
      ![Details for bastion-host](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/3c-get_bastion_details.png)

4. Complete deployment on the bastion virtual machine. These steps will be completed from the command
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
  
   3. Initialize the KnowEnG Platform. In your SSH session on `bastion-host`, run 
      the following two commands:
   
      ```
      wget https://raw.githubusercontent.com/KnowEng/Kubernetes_AWS/master/cloudformation/knowcfnscript.sh
      sh knowcfnscript.sh
      ```
   
      The script will take 40 minutes or so to complete. Upon successful completion, the 
      script will print a URL to open in your web browser.

      ![Success message with URL](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/5e-get_url.png)
   
   4. Open the KnowEnG Platform interface. In the web browser on your local machine, open 
      the URL printed at the end of step 5.iii. Sign in with username `knowenguser` and password
      `KNOWENGUSER1234`.

# Deleting a KnowEnG Platform Deployment

1. In your SSH session on `bastion-host`, run `kubectl delete svc nest-public-lb`.

2. In the AWS Console, open the `Services` dropdown near the top-left corner and select `EFS`
   from the `Storage` section.

   ![Dropdown to select EFS](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/d2a-open_efs.png)

   In the table of file systems, select the one whose name matches the stack name you selected in
   step 2.ii of the deployment procedure. Press the `Actions` button above the table and 
   select `Delete file system`. Follow the on-screen instructions to confirm and complete the deletion.

   ![Dropdown to delete EFS](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/d2b-delete_efs.png)

3. In the AWS Console, open the `Services` dropdown near the top-left corner and select
   `CloudFormation` from the `Management & Governance` section. 

   ![Dropdown to select CloudFormation](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/d3a-open_cfn.png)
   
   In the table of stacks,
   find and select the one you created in step 2 of the deployment procedure. (Note there 
   will be a similarly-named stack labeled `NESTED`. Do not delete the `NESTED` stack. 
   It will be deleted automatically when you delete the stack you created in step 2
   of the deployment procedure.) Press the `Actions` button above the table
   and select `Delete Stack`. Follow the on-screen instructions to confirm and
   complete the deletion. You will see the stack's status change to `DELETE_IN_PROGRESS`.
   Refresh the page until the stack no longer appears in the table, which might take 10
   minutes or so.

   ![Dropdown to delete stack](https://github.com/KnowEnG/Kubernetes_AWS/raw/master/cloudformation/img/d3b-delete_stack.png)
