# Export a list of ENIs with 'available' status
eni_ids=$(aws ec2 describe-network-interfaces \
    --filters Name=status,Values=available \
    --query 'NetworkInterfaces[*].NetworkInterfaceId' \
    --output text)

# Iterate over each ENI ID and delete them
for eni_id in $eni_ids; do
    aws ec2 delete-network-interface --network-interface-id $eni_id
	echo "$eni_id : Deleted"
done