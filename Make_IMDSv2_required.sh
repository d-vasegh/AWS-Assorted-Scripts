# Export a list of instance IDs with IMDSv2 as optional
instance_ids=$(aws ec2 describe-instances \
    --query 'Reservations[].Instances[?MetadataOptions.HttpEndpoint == `enabled` && MetadataOptions.HttpTokens == `optional`].[InstanceId]' \
    --output text)

# Iterate over each instance ID
for instance_id in $instance_ids; do
    # Modify the IMDSv2 settings to required
    aws ec2 modify-instance-metadata-options \
        --instance-id $instance_id \
        --http-tokens required \
        --http-endpoint enabled

    # Echo that the instance has been modified
    echo "Instance $instance_id : Modified."
done