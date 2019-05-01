EFS_PROVISIONER_POD_ID=$(kubectl get pods -l app=efs-provisioner -ojsonpath='{.items[0].metadata.name}')
EFS_DNS=$(kubectl get pod $EFS_PROVISIONER_POD_ID -ojsonpath='{.spec.volumes[?(@.name=="pv-volume")].nfs.server}')
EFS_ID=$(echo "$EFS_DNS" | cut -f1 -d.)
EFS_REGION=$(echo "$EFS_DNS" | cut -f3 -d.)

EFS_MOUNT_TARGETS=$(aws efs describe-mount-targets --file-system-id $EFS_ID --region $EFS_REGION --query "MountTargets[*].MountTargetId" --output text)
for EFS_MOUNT_TARGET in $EFS_MOUNT_TARGETS ; do
  aws efs delete-mount-target --mount-target-id $EFS_MOUNT_TARGET --region $EFS_REGION
done

aws efs delete-file-system --file-system-id $EFS_ID --region $EFS_REGION
while [ $? -ne 0 ]; do
  echo "attempting to delete EFS again in 10 seconds..."
  sleep 10s
  aws efs delete-file-system --file-system-id $EFS_ID --region $EFS_REGION
done

HAS_DNS_NODE_NAME=$(kubectl get nodes -l has-dns=true -ojsonpath='{.items[0].metadata.name}')
HAS_DNS_EC2_LONG_ID=$(kubectl get node $HAS_DNS_NODE_NAME -ojsonpath='{.spec.providerID}')
HAS_DNS_EC2_ID=$(echo $HAS_DNS_EC2_LONG_ID | sed -e "s/^.*\///")
HAS_DNS_EC2_REGION=$(echo $HAS_DNS_EC2_LONG_ID | sed -e "s/^aws:\/\/\///" -e "s/[a-z]*\/.*$//")

CLUSTER_NAME=$(kops get cluster -oyaml | grep name | head -n 1 | sed -e "s/^.*:\s//")

PUBLIC_WEB_SG_ID=$(aws ec2 describe-instances --instance-ids $HAS_DNS_EC2_ID --region $HAS_DNS_EC2_REGION --query "Reservations[0].Instances[0].SecurityGroups[?GroupName!='nodes.$CLUSTER_NAME'].GroupId" --output text)
CLUSTER_SG_ID=$(aws ec2 describe-instances --instance-ids $HAS_DNS_EC2_ID --region $HAS_DNS_EC2_REGION --query "Reservations[0].Instances[0].SecurityGroups[?GroupName=='nodes.$CLUSTER_NAME'].GroupId" --output text)

aws ec2 modify-instance-attribute --instance-id $HAS_DNS_EC2_ID --region $HAS_DNS_EC2_REGION --groups $CLUSTER_SG_ID
aws ec2 delete-security-group --group-id $PUBLIC_WEB_SG_ID --region $HAS_DNS_EC2_REGION

helm delete support --purge
kubectl delete namespace support

STATESTORE=$(kops get cluster -oyaml | grep configBase | sed -e "s/^.*\/\///" -e "s/\/.*$//")

kops delete cluster $CLUSTER_NAME --yes

rm -rf $HOME/.kops

aws s3api delete-objects \
  --bucket $STATESTORE \
  --delete "$(aws s3api list-object-versions \
    --bucket $STATESTORE \
    --output=json \
    --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
    
aws s3api delete-objects \
  --bucket $STATESTORE \
  --delete "$(aws s3api list-object-versions \
    --bucket $STATESTORE \
    --output=json \
    --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
    
aws s3api delete-bucket --bucket $STATESTORE --region us-east-1

echo "
Done. Refer to the README for additional instructions.
"
