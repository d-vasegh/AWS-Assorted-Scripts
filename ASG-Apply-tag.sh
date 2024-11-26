aws autoscaling describe-auto-scaling-groups \
  --query 'AutoScalingGroups[*].AutoScalingGroupName' \
  --output text | tr '\t' '\n' | while read asg; do
    aws autoscaling create-or-update-tags --tags \
      "ResourceId=${asg},ResourceType=auto-scaling-group,Key='new-tag-key',Value='new-tag-value',PropagateAtLaunch=true"
    echo "Tag applied to ASG: ${asg}"
  done