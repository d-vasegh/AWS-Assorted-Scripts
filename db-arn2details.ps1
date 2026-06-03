param(
    [string]$InputFile = "H:\Downloads\db-arn.txt",
    [string]$OutputFile = "H:\Downloads\rds_engines.csv",
    [string]$RoleName = "OrganizationAccountAccessRole",
    [int]$AssumeRoleDuration = 1000
)

# Read ARNs
if (-not (Test-Path $InputFile)) {
    Write-Error "Input file '$InputFile' not found. Provide a valid path or use -InputFile parameter."
    exit 1
}

$arns = Get-Content -Path $InputFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

# Save current environment creds to restore later
$origAwsAccessKey = $env:AWS_ACCESS_KEY_ID
$origAwsSecretKey = $env:AWS_SECRET_ACCESS_KEY
$origAwsSession = $env:AWS_SESSION_TOKEN

$results = @()

foreach ($arn in $arns) {
    $arn = $arn.Trim()
    # Expect: arn:aws:rds:region:account-id:db:db-instance-id
    $parts = $arn -split ":"
    if ($parts.Count -lt 7) {
        $results += [PSCustomObject]@{
            ARN = $arn
            AccountID = $null
            Region = $null
            DBName = $null
            Engine = $null
            Version = $null
            Error = "Unexpected ARN format"
        }
        continue
    }

    $region = $parts[3]
    $account = $parts[4]
    $resource = $parts[5]
    $dbid = $parts[6]

    $errorMsg = $null

    # If RoleName provided, try to assume role in target account
    $assumed = $false
    if ($RoleName -and $RoleName.Trim() -ne "") {
        $roleArn = "arn:aws:iam::$account:role/$RoleName"
        $assumeJson = aws sts assume-role --role-arn $roleArn --role-session-name "GetRDSInfo-$account-$dbid" --duration-seconds $AssumeRoleDuration --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            $errorMsg = "AssumeRole failed for ${account}: ${assumeJson}"
        } else {
            try {
                $creds = $assumeJson | ConvertFrom-Json
                $env:AWS_ACCESS_KEY_ID = $creds.Credentials.AccessKeyId
                $env:AWS_SECRET_ACCESS_KEY = $creds.Credentials.SecretAccessKey
                $env:AWS_SESSION_TOKEN = $creds.Credentials.SessionToken
                $assumed = $true
            } catch {
                $errorMsg = "Failed parsing AssumeRole response: $_"
            }
        }
    }

    # Call AWS CLI to describe DB instance
    $cmd = aws rds describe-db-instances --region $region --db-instance-identifier $dbid --query "DBInstances[0].[DBInstanceIdentifier,Engine,EngineVersion]" --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        if (-not $errorMsg) { $errorMsg = $cmd }
        $dbName = $null; $engine = $null; $version = $null
    } else {
        try {
            $info = $cmd | ConvertFrom-Json
            $dbName = if ($info -is [System.Array]) { $info[0] } else { $info[0] }
            $engine = $info[1]
            $version = $info[2]
        } catch {
            $errorMsg = "Failed parsing describe-db-instances JSON: $_";
            $dbName = $null; $engine = $null; $version = $null
        }
    }

    # Restore original env credentials (so next assume uses fresh state)
    if ($assumed) {
        $env:AWS_ACCESS_KEY_ID = $origAwsAccessKey
        $env:AWS_SECRET_ACCESS_KEY = $origAwsSecretKey
        $env:AWS_SESSION_TOKEN = $origAwsSession
    }

    $results += [PSCustomObject]@{
        ARN = $arn
        AccountID = $account
        Region = $region
        DBName = $dbName
        Engine = $engine
        Version = $version
        Error = $errorMsg
    }
}

# Export to CSV
$results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
Write-Host "Exported results to $OutputFile"