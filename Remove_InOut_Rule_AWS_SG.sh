#!/bin/bash

# Get a list of all active AWS regions
regions=$(aws ec2 describe-regions --query "Regions[].RegionName" --output text)

# Loop through each region
for region in $regions; do
    echo "Checking region: $region"
    
    # Get the default security group ID for each VPC in the region
    default_sg_ids=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filters Name=group-name,Values=default \
        --query "SecurityGroups[].GroupId" \
        --output text)
    
    # Loop through each default security group
    for sg_id in $default_sg_ids; do
        echo "Processing security group: $sg_id in region: $region"
        
        # Remove all inbound rules
        inbound_rules=$(aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query "SecurityGroups[].IpPermissions" \
            --output json)
        
        # Check if there are any inbound rules
        if [ "$inbound_rules" != "[]" ]; then
            for rule in $(echo "$inbound_rules" | jq -c '.[]'); do
                aws ec2 revoke-security-group-ingress \
                    --region "$region" \
                    --group-id "$sg_id" \
                    --ip-permissions "$rule"
                echo "Removed an inbound rule for security group: $sg_id"
            done
        else
            echo "No inbound rules to remove for security group: $sg_id"
        fi
        
        # Remove all outbound rules
        outbound_rules=$(aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query "SecurityGroups[].IpPermissionsEgress" \
            --output json)
        
        # Check if there are any outbound rules
        if [ "$outbound_rules" != "[]" ]; then
            for rule in $(echo "$outbound_rules" | jq -c '.[]'); do
                aws ec2 revoke-security-group-egress \
                    --region "$region" \
                    --group-id "$sg_id" \
                    --ip-permissions "$rule"
                echo "Removed an outbound rule for security group: $sg_id"
            done
        else
            echo "No outbound rules to remove for security group: $sg_id"
        fi
    done
done

echo "Script completed."
