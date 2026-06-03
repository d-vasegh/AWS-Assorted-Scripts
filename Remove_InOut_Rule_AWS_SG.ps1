[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$Region,
    [switch]$SkipIngress,
    [switch]$SkipEgress
)

function Invoke-AwsCliJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & aws @Arguments --output json 2>&1
    $outputText = $output -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0) {
        throw "AWS CLI command failed: aws $($Arguments -join ' ') --output json`n$outputText"
    }

    if ([string]::IsNullOrWhiteSpace($outputText)) {
        return $null
    }

    return ($outputText | ConvertFrom-Json)
}

function Get-AwsRegionName {
    param(
        [string[]]$Region
    )

    if ($Region -and $Region.Count -gt 0) {
        return $Region
    }

    return Invoke-AwsCliJson -Arguments @(
        "ec2",
        "describe-regions",
        "--query",
        "Regions[].RegionName"
    )
}

function Remove-SecurityGroupRuleSet {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Region,

        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Ingress", "Egress")]
        [string]$Direction,

        [object[]]$Rules = @()
    )

    if (-not $Rules -or $Rules.Count -eq 0) {
        Write-Host "No $($Direction.ToLower()) rules to remove for security group: $GroupId"
        return
    }

    $awsAction = if ($Direction -eq "Ingress") {
        "revoke-security-group-ingress"
    } else {
        "revoke-security-group-egress"
    }

    foreach ($rule in $Rules) {
        $ruleJson = $rule | ConvertTo-Json -Depth 20 -Compress
        $target = "$Direction rule for security group $GroupId in region $Region"

        if ($PSCmdlet.ShouldProcess($target, "Remove")) {
            Invoke-AwsCliJson -Arguments @(
                "ec2",
                $awsAction,
                "--region",
                $Region,
                "--group-id",
                $GroupId,
                "--ip-permissions",
                $ruleJson
            ) | Out-Null

            Write-Host "Removed a $($Direction.ToLower()) rule for security group: $GroupId"
        }
    }
}

function Remove-InOutRuleAwsSecurityGroup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string[]]$Region,
        [switch]$SkipIngress,
        [switch]$SkipEgress
    )

    $regions = Get-AwsRegionName -Region $Region

    foreach ($regionName in $regions) {
        Write-Host "Checking region: $regionName"

        $securityGroups = Invoke-AwsCliJson -Arguments @(
            "ec2",
            "describe-security-groups",
            "--region",
            $regionName,
            "--filters",
            "Name=group-name,Values=default",
            "--query",
            "SecurityGroups[].{GroupId:GroupId,IpPermissions:IpPermissions,IpPermissionsEgress:IpPermissionsEgress}"
        )

        if (-not $securityGroups -or $securityGroups.Count -eq 0) {
            Write-Host "No default security groups found in region: $regionName"
            continue
        }

        foreach ($securityGroup in $securityGroups) {
            $groupId = $securityGroup.GroupId
            Write-Host "Processing security group: $groupId in region: $regionName"

            if (-not $SkipIngress) {
                Remove-SecurityGroupRuleSet `
                    -Region $regionName `
                    -GroupId $groupId `
                    -Direction "Ingress" `
                    -Rules @($securityGroup.IpPermissions) `
                    -WhatIf:$WhatIfPreference
            }

            if (-not $SkipEgress) {
                Remove-SecurityGroupRuleSet `
                    -Region $regionName `
                    -GroupId $groupId `
                    -Direction "Egress" `
                    -Rules @($securityGroup.IpPermissionsEgress) `
                    -WhatIf:$WhatIfPreference
            }
        }
    }

    Write-Host "Script completed."
}

Set-Alias -Name Remove_InOut_Rule_AWS_SG -Value Remove-InOutRuleAwsSecurityGroup

if ($MyInvocation.InvocationName -ne ".") {
    Remove-InOutRuleAwsSecurityGroup `
        -Region $Region `
        -SkipIngress:$SkipIngress `
        -SkipEgress:$SkipEgress `
        -WhatIf:$WhatIfPreference
}
