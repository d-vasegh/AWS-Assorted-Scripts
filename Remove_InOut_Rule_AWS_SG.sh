#!/bin/bash
# Run this script right after creating a new AWS account
set -euo pipefail

DRY_RUN=true   # set to false to apply changes
LOG_FILE="sg_cleanup_$(date +%F).log"

log() {
    echo "$(date '+%F %T') | $1" | tee -a "$LOG_FILE"
}

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        log "[DRY-RUN] $*"
    else
        log "[EXEC] $*"
        eval "$@"
    fi
}

log "Starting default security group cleanup..."

regions=$(aws ec2 describe-regions \
    --query "Regions[].RegionName" \
    --output text)

for region in $regions; do
    log "Checking region: $region"

    default_sg_ids=$(aws ec2 describe-security-groups \
        --region "$region" \
        --filters Name=group-name,Values=default \
        --query "SecurityGroups[].GroupId" \
        --output text)

    for sg_id in $default_sg_ids; do
        log "Processing SG: $sg_id (region: $region)"

        # Get inbound rules
        inbound_rules=$(aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissions" \
            --output json)

        if [ "$inbound_rules" != "[]" ]; then
            run_cmd "aws ec2 revoke-security-group-ingress \
                --region $region \
                --group-id $sg_id \
                --ip-permissions '$inbound_rules'"
        else
            log "No inbound rules for $sg_id"
        fi

        # Get outbound rules
        outbound_rules=$(aws ec2 describe-security-groups \
            --region "$region" \
            --group-ids "$sg_id" \
            --query "SecurityGroups[0].IpPermissionsEgress" \
            --output json)

        if [ "$outbound_rules" != "[]" ]; then
            run_cmd "aws ec2 revoke-security-group-egress \
                --region $region \
                --group-id $sg_id \
                --ip-permissions '$outbound_rules'"
        else
            log "No outbound rules for $sg_id"
        fi
    done
done

log "Completed."
