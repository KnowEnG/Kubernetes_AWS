
## Zero-To-KnowDev ([https://dev.knoweng.org](https://dev.knoweng.org))

### Overview

* [To Clean the Resources](#danger-zone-to-clean-the-resources)

### Steps

1. Create an EC2 instance from the Ubuntu 18 image with size t2.micro. Add IAM Role KnowKubeKOPS. Add Name tag with value KnowDevKOPS. Make sure the security group allows ssh access from your IP.

   Note: If you need to recreate the KnowKubeKOPS role, it should have the following permissions:

   - AmazonEC2FullAccess  
   - AmazonS3FullAccess  
   - IAMFullAccess  
   - AmazonVPCFullAccess  
   - AmazonElasticFileSystemFullAccess  

2. SSH into the instance using the ssh key used/created while spinning up the instance.

   `ssh -i <ssh-key>.pem ubuntu@{ip/fqdn}`

   `sudo apt update && sudo apt upgrade -y`

3. Prepare the SSL certificate and key. If the certificate and key already exist, copy them
   to the EC2 instance. If the certificate and key don't already exist, you can create a
   self-signed certificate by modifying and running the following command on the EC2 instance:

   `openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -keyout knoweng.key -out knoweng.crt -subj /CN=dev.knoweng.org`

   Note the full paths to the certificate file and key file. They'll be needed in the next step.

4. Run the installer script:

   `wget https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/dev/install-knoweng.sh`

   `./install-knoweng.sh`

   The script will prompt for input and then run for several minutes.

5. Update the DNS record (in IPAM) for dev.knoweng.org to point to the IP address printed
   at the end of the script output.

6. Stop KnowDevKOPS until further use and detach/modify security group for no ssh access


## DANGER ZONE! To Clean the Resources:

On KnowDevKOPS, run the following:

   `wget https://raw.githubusercontent.com/KnowEnG/Kubernetes_AWS/master/dev/uninstall-knoweng.sh`

   `./uninstall-knoweng.sh`

This may take a while.

When the script finishes, verify via Console/CLI that all EC2 nodes from the deployment are terminated.
You can manually terminate KnowDevKOPS using the Console.

Finally, remove A record for "dev.knoweng.org" in the IPAM manager, so that UIUC owned domain doesn't point to an arbitrary machine.
