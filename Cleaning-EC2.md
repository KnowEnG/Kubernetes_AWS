
## Cleaning an EC2 instance (Sample: KnowPipes)

### Overview

The purpose of this document is to walk through the steps of terminating an EC2 instance and cleaning the resources associated with it.

### Note the Resources attached to an EC2 Instance:

1. EC2 Instance (KnowPipes)
2. Security Group (knowpipes)
3. Root/block device (/dev/sda1)
4. Elastic ip Address (if any)
5. IPAM DNS (if any)
6. Optional: vpc (if not default-vpc)

### Steps

1. AWS Console: Select the instance to terminate (e.g. KnowPipes)

2. Check if the **Termination Protection** is turned on:

    Actions > Instance Settings > Change Termination Protection > **Yes, Disable**

3. Terminate the Instance:

    Actions > Instance State > Terminate > Release attached Elastic IPs (check if unchecked) > Note if EBS volumes is set to delete on termination (note the  > **Yes, Terminate**

4. Delete the EBS Volume(s):

    If the EBS volumes was set to not delete on termination:

    Go to EC2 dashboard > Volumes > Select the Volume id (which should now be available) > Actions > Delete Volume

5. Delete the Security Group(s):

    Go to EC2 dashboard > Security Groups > Select the Security Group that belonged to the terminated EC2 instance but now is orphan (not attached to any resource, otherwise delete will fail) > Actions > Delete Security Group

    If the Security Group is **associated with one or more network interfaces**, either detach from them before deleting or wait till other resources are terminated/deleted. The prompt will let you  view the associated network interfaces and prevent deletion.

6. Delete DNS entry from IPAM manager:

    Go to [IPAM](https://ipam.illinois.edu/) manager > Select the DNS record for the hostname > Delete

    This will avoid pointing our Domain to some arbitrary VM that someone creates and AWS attaches to that VM. Specially with University owned Domains. It may take a while for DNS to propagate, depending on TTL (Time to Live) setting for the Record.

