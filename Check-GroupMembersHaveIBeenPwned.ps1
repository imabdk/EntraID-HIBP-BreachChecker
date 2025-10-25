<#
.SYNOPSIS
    Checks Entra ID group members for data breaches using Have I Been Pwned.

.DESCRIPTION
    This script retrieves all members of specified Entra ID group(s), including nested group members,
    then checks each email address against the Have I Been Pwned database for known data breaches.
    Generates an HTML report with the results. Optionally generates a PDF report if -GeneratePdf switch is used.
    
    IMPORTANT: This script requires a Have I Been Pwned API subscription to function. The Have I Been Pwned 
    API is a paid service that provides programmatic access to breach data. You must subscribe at:
    https://haveibeenpwned.com/API/Key
    
    The API key is required to authenticate your requests and is rate-limited based on your subscription tier.
    Without a valid API key, the breach checking functionality will not work.

.PARAMETER GroupId
    The Object ID(s) of the Entra ID group(s). Accepts single ID or array of IDs.

.PARAMETER GroupName
    The display name(s) of the Entra ID group(s). Accepts single name or array of names.

.PARAMETER ExpandNestedGroups
    Switch to enable recursive expansion of nested groups (default: $true).

.PARAMETER ApiKey
    API Key for Have I Been Pwned (required for breach checking).
    Obtain your API key from: https://haveibeenpwned.com/API/Key
    This is a paid subscription service from Have I Been Pwned.
    
    For testing purposes, you can use the test API key: 00000000000000000000000000000000
    Note: The test API key only works for specific test email addresses documented in the HIBP API.

.PARAMETER SkipBreachCheck
    Skip the breach checking and only retrieve group members.

.PARAMETER GeneratePdf
    Switch to enable PDF report generation (requires Chrome or Edge).

.PARAMETER RateLimitPerMinute
    The rate limit for your Have I Been Pwned API subscription (requests per minute).
    Valid values: '10', '50', '100', '500', '1000'
    
    Subscription tiers:
    - '10'   = 10 requests/minute   (Pwned 1 - 10 second delay per request)
    - '50'   = 50 requests/minute   (Pwned 2 - 1.2 second delay per request)
    - '100'  = 100 requests/minute  (Pwned 3 - 600ms delay per request)
    - '500'  = 500 requests/minute  (Pwned 4 - 120ms delay per request)
    - '1000' = 1000 requests/minute (Pwned 5 - 60ms delay per request)
    
    Default: '10' (Pwned 1 tier)
    The script will automatically calculate the appropriate delay between API calls.
    For custom rate limits, contact your API provider.

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "IT Department" -ApiKey "your-api-key" -RateLimitPerMinute '100'
    
    Checks all members using a Pwned 3 subscription tier (100 requests/minute).

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "Team - IT Helpdesk" -ApiKey "your-api-key" -GeneratePdf
    
    Checks the group members and generates both HTML and PDF reports.

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupId "12345678-1234-1234-1234-123456789abc" -ApiKey "your-api-key"
    
    Checks group members using the group's Object ID instead of display name.

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "IT Department" -ApiKey "00000000000000000000000000000000"
    
    Uses the test API key for testing purposes (only works with specific test email addresses).

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "IT Department" -ApiKey "your-api-key" -RateLimitPerMinute '10'
    
    Uses the default rate limit of 10 requests per minute (Basic subscription).

.EXAMPLE
    .\Check-GroupMembersHaveIBeenPwned.ps1 -GroupName "Large Department" -ApiKey "your-api-key" -RateLimitPerMinute '100'
    
    Uses a Professional subscription with 100 requests per minute for faster processing of large groups.

.NOTES
    Author: MAB
    Date: October 24, 2025
    Website: https://www.imab.dk
    
    Requirements:
    - Microsoft.Graph PowerShell module (Install-Module Microsoft.Graph.Groups, Microsoft.Graph.Users)
    - HaveIBeenPwned PowerShell module (Install-Module HaveIBeenPwned)
    - Have I Been Pwned API subscription (https://haveibeenpwned.com/API/Key)
    - Chrome or Microsoft Edge (optional, for PDF generation)
    
    API Information:
    The Have I Been Pwned API is a commercial service. Free access is not available for the breach search 
    functionality used by this script. Visit https://haveibeenpwned.com/API/Key for pricing and subscription details.
    
    For testing purposes only, you can use the test API key: 00000000000000000000000000000000
    Note that the test key only works with specific test email addresses as documented in the HIBP API documentation.
#>

[CmdletBinding(DefaultParameterSetName = 'ById')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
    [string[]]$GroupId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
    [string[]]$GroupName,

    [Parameter(Mandatory = $false)]
    [switch]$ExpandNestedGroups,

    [Parameter(Mandatory = $true)]
    [string]$ApiKey,

    [Parameter(Mandatory = $false)]
    [switch]$SkipBreachCheck,

    [Parameter(Mandatory = $false)]
    [switch]$GeneratePdf,

    [Parameter(Mandatory = $false)]
    [ValidateSet('10', '50', '100', '500', '1000')]
    [string]$RateLimitPerMinute = '10'
)

# Set default behavior for ExpandNestedGroups if not explicitly specified
if (-not $PSBoundParameters.ContainsKey('ExpandNestedGroups')) {
    $ExpandNestedGroups = $true
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  imab.dk - Have I Been Pwned Tool" -ForegroundColor Cyan
Write-Host "  Data Breach Check for Entra ID" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

#region Module Checks and Imports

# Check if Microsoft.Graph modules are installed
Write-Host "Checking required modules..." -ForegroundColor Cyan

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
    Write-Error "Microsoft.Graph.Groups module is not installed. Please install it using: Install-Module Microsoft.Graph.Groups -Scope CurrentUser"
    exit 1
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
    Write-Error "Microsoft.Graph.Users module is not installed. Please install it using: Install-Module Microsoft.Graph.Users -Scope CurrentUser"
    exit 1
}

# Check if HaveIBeenPwned module is installed (only if not skipping breach check)
if (-not $SkipBreachCheck) {
    if (-not (Get-Module -ListAvailable -Name HaveIBeenPwned)) {
        Write-Host "HaveIBeenPwned module not found. Installing..." -ForegroundColor Yellow
        try {
            Install-Module -Name HaveIBeenPwned -Scope CurrentUser -Force -AllowClobber
            Write-Host "Module installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Error "Failed to install HaveIBeenPwned module. Please run: Install-Module -Name HaveIBeenPwned -Scope CurrentUser"
            exit 1
        }
    }
    Import-Module HaveIBeenPwned
}

# Import required modules
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

Write-Host "All required modules loaded successfully`n" -ForegroundColor Green

#endregion

#region Connect to Microsoft Graph

try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "GroupMember.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph`n" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

#endregion

#region Group Member Retrieval

# Initialize collection to track processed groups and members
$processedGroups = @{}
$allMembers = @()

# Function to recursively get group members
function Get-GroupMembersRecursive {
    param(
        [string]$GroupObjectId,
        [int]$Level = 0
    )

    # Prevent infinite loops by tracking processed groups
    if ($processedGroups.ContainsKey($GroupObjectId)) {
        Write-Verbose "Group $GroupObjectId already processed, skipping to avoid circular reference"
        return
    }

    $processedGroups[$GroupObjectId] = $true
    $indent = "  " * $Level

    try {
        # Get group details
        $group = Get-MgGroup -GroupId $GroupObjectId -ErrorAction Stop
        Write-Host "$($indent)Processing group: $($group.DisplayName) (ID: $GroupObjectId)" -ForegroundColor Yellow

        # Get all members of the group
        $members = Get-MgGroupMember -GroupId $GroupObjectId -All -ErrorAction Stop

        foreach ($member in $members) {
            $memberType = $member.AdditionalProperties["@odata.type"]

            if ($memberType -eq "#microsoft.graph.user") {
                # It's a user - get full user details
                try {
                    $user = Get-MgUser -UserId $member.Id -Property "Id,DisplayName,UserPrincipalName,Mail,JobTitle,Department,AccountEnabled" -ErrorAction Stop
                    
                    Write-Host "$($indent)  [User] $($user.DisplayName) ($($user.UserPrincipalName))" -ForegroundColor Green

                    # Create custom object for the member
                    $memberObject = [PSCustomObject]@{
                        Type              = "User"
                        DisplayName       = $user.DisplayName
                        UserPrincipalName = $user.UserPrincipalName
                        Mail              = $user.Mail
                        JobTitle          = $user.JobTitle
                        Department        = $user.Department
                        AccountEnabled    = $user.AccountEnabled
                        ObjectId          = $user.Id
                        ParentGroup       = $group.DisplayName
                        ParentGroupId     = $group.Id
                        NestingLevel      = $Level
                    }

                    $script:allMembers += $memberObject
                }
                catch {
                    Write-Warning "$($indent)  Failed to get details for user $($member.Id): $_"
                }
            }
            elseif ($memberType -eq "#microsoft.graph.group" -and $ExpandNestedGroups) {
                # It's a nested group - recurse if enabled
                $nestedGroup = Get-MgGroup -GroupId $member.Id -ErrorAction Stop
                Write-Host "$($indent)  [Nested Group] $($nestedGroup.DisplayName)" -ForegroundColor Cyan
                
                # Add nested group to results
                $groupObject = [PSCustomObject]@{
                    Type              = "Group"
                    DisplayName       = $nestedGroup.DisplayName
                    UserPrincipalName = $null
                    Mail              = $nestedGroup.Mail
                    JobTitle          = $null
                    Department        = $null
                    AccountEnabled    = $null
                    ObjectId          = $nestedGroup.Id
                    ParentGroup       = $group.DisplayName
                    ParentGroupId     = $group.Id
                    NestingLevel      = $Level
                }
                $script:allMembers += $groupObject

                # Recursively process the nested group
                Get-GroupMembersRecursive -GroupObjectId $member.Id -Level ($Level + 1)
            }
            elseif ($memberType -eq "#microsoft.graph.group") {
                # Nested group but not expanding
                $nestedGroup = Get-MgGroup -GroupId $member.Id -ErrorAction Stop
                Write-Host "$($indent)  [Nested Group] $($nestedGroup.DisplayName) (not expanded)" -ForegroundColor DarkCyan
            }
            else {
                # Other types (service principals, devices, etc.)
                Write-Host "$($indent)  [Other] $($member.Id) (Type: $memberType)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Error "$($indent)Failed to process group ${GroupObjectId}: $_"
    }
}

# Main execution for group retrieval
try {
    # Resolve group IDs if group names were provided
    $GroupIdsToProcess = @()
    
    if ($PSCmdlet.ParameterSetName -eq 'ByName') {
        Write-Host "Looking up $($GroupName.Count) group(s) by name..." -ForegroundColor Cyan
        
        foreach ($name in $GroupName) {
            Write-Host "  Searching for: $name" -ForegroundColor Cyan
            
            # Search for groups by display name (using ConsistencyLevel for advanced query)
            $groups = @(Get-MgGroup -Search "displayName:$name" -ConsistencyLevel eventual -ErrorAction SilentlyContinue)
            
            # If search didn't work, try getting all and filtering
            if ($groups.Count -eq 0) {
                Write-Verbose "Search didn't find results, trying filter approach..."
                $groups = @(Get-MgGroup -All -ErrorAction Stop | Where-Object { $_.DisplayName -eq $name })
            }
            
            if ($groups.Count -eq 0) {
                Write-Warning "No group found with name: $name - skipping"
                continue
            }
            
            # Filter to exact match if we got multiple results
            $exactMatches = @($groups | Where-Object { $_.DisplayName -eq $name })
            if ($exactMatches.Count -eq 1) {
                $groups = $exactMatches
            }
            elseif ($exactMatches.Count -gt 1) {
                Write-Warning "Multiple groups found with exact name: $name"
                $exactMatches | Format-Table DisplayName, Id, Mail
                Write-Warning "Please use -GroupId parameter to specify the exact group - skipping"
                continue
            }
            
            $group = $groups[0]
            $GroupIdsToProcess += $group.Id
            Write-Host "    Found: $($group.DisplayName) (ID: $($group.Id))" -ForegroundColor Green
        }
        
        if ($GroupIdsToProcess.Count -eq 0) {
            Write-Error "No valid groups found"
            exit 1
        }
    }
    else {
        # Using GroupId parameter
        $GroupIdsToProcess = $GroupId
    }

    # Start recursive member retrieval for all groups
    Write-Host "`nStarting recursive member retrieval for $($GroupIdsToProcess.Count) group(s)..." -ForegroundColor Cyan
    Write-Host "================================`n" -ForegroundColor Cyan
    
    foreach ($groupId in $GroupIdsToProcess) {
        Get-GroupMembersRecursive -GroupObjectId $groupId
        Write-Host "" # Add spacing between groups
    }

    # Display summary
    Write-Host "`n================================" -ForegroundColor Cyan
    Write-Host "Group Retrieval Summary:" -ForegroundColor Cyan
    Write-Host "Groups processed: $($GroupIdsToProcess.Count)" -ForegroundColor Green
    Write-Host "Total members found: $($allMembers.Count)" -ForegroundColor Green
    $uniqueUsers = $allMembers | Where-Object { $_.Type -eq 'User' } | Select-Object -Unique ObjectId
    Write-Host "  Unique Users: $($uniqueUsers.Count)" -ForegroundColor Green
    Write-Host "  Nested Groups: $(($allMembers | Where-Object { $_.Type -eq 'Group' } | Select-Object -Unique ObjectId).Count)" -ForegroundColor Green
    Write-Host "================================`n" -ForegroundColor Cyan
    
    # Store group names and tenant info before disconnecting (for use in reports later)
    $script:ProcessedGroupNames = @()
    foreach ($id in $GroupIdsToProcess) {
        try {
            $groupInfo = Get-MgGroup -GroupId $id -ErrorAction Stop
            if ($groupInfo) {
                $script:ProcessedGroupNames += $groupInfo.DisplayName
            }
        }
        catch {
            Write-Warning "Could not retrieve name for group ID: $id"
        }
    }
    
    # Get tenant information
    try {
        $orgInfo = Get-MgOrganization -ErrorAction Stop
        $script:TenantName = if ($orgInfo.DisplayName) { $orgInfo.DisplayName } else { "Unknown" }
        $script:TenantDomain = if ($orgInfo.VerifiedDomains) { 
            ($orgInfo.VerifiedDomains | Where-Object { $_.IsDefault -eq $true }).Name 
        } else { 
            "Unknown" 
        }
    }
    catch {
        Write-Warning "Could not retrieve tenant information: $_"
        $script:TenantName = "Unknown"
        $script:TenantDomain = "Unknown"
    }
}
catch {
    Write-Error "An error occurred during group retrieval: $_"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph`n" -ForegroundColor Green
}

#endregion

#region Breach Checking

if ($SkipBreachCheck) {
    Write-Host "Skipping breach check as requested." -ForegroundColor Yellow
    Write-Host "`nFinal Results:" -ForegroundColor Cyan
    $allMembers | Sort-Object DisplayName | Format-Table Type, DisplayName, UserPrincipalName, Department, ParentGroup, NestingLevel -AutoSize
    exit 0
}

# Filter to only users for breach checking
$usersToCheck = $allMembers | Where-Object { $_.Type -eq 'User' -and $_.Mail }

if ($usersToCheck.Count -eq 0) {
    Write-Host "No users with email addresses found to check for breaches." -ForegroundColor Yellow
    exit 0
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Starting Breach Check" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Calculate delay based on rate limit
# Rate limit is per minute, so convert to milliseconds per request
$delayMs = [math]::Ceiling((60000 / [int]$RateLimitPerMinute))
Write-Host "API Rate Limit: $RateLimitPerMinute requests/minute" -ForegroundColor Cyan
Write-Host "Delay between requests: $delayMs ms" -ForegroundColor Cyan
Write-Host "Checking $($usersToCheck.Count) email addresses for breaches..." -ForegroundColor Cyan
Write-Host "Estimated time: $([math]::Ceiling(($usersToCheck.Count * $delayMs) / 60000)) minute(s)`n" -ForegroundColor Cyan

# Initialize results array for breach checking
$breachResults = @()

# Process each user for breach checking
foreach ($user in $usersToCheck) {
    $Email = $user.Mail

    Write-Host "Checking: $Email" -ForegroundColor Cyan

    $breachResult = [PSCustomObject]@{
        Email = $Email
        DisplayName = $user.DisplayName
        Department = $user.Department
        ParentGroup = $user.ParentGroup
        BreachCount = 0
        Breaches = @()
        Status = "Checked"
    }

    try {
        # Get breach data for the email address
        $Breaches = Get-PwnedAccount -EmailAddress $Email -ApiKey $ApiKey -UserAgent 'HaveIBeenPwnedScript'
        
        # Rate limiting: Sleep based on subscription tier
        Start-Sleep -Milliseconds $delayMs

        if ($Breaches -and $Breaches.Count -gt 0) {
            Write-Host "  [!] BREACHED: $($Breaches.Count) breaches found" -ForegroundColor Red
            
            $BreachDetails = @()
            foreach ($Breach in $Breaches) {
                # Skip if breach has no name (invalid data)
                if (-not $Breach.Name) {
                    continue
                }
                
                Write-Host "     - $($Breach.Name) (Date: $($Breach.BreachDate))" -ForegroundColor Yellow
                if ($Breach.DataClasses) {
                    Write-Host "       Data exposed: $($Breach.DataClasses -join ', ')" -ForegroundColor Gray
                }
                
                # Collect breach details
                $BreachDetails += [PSCustomObject]@{
                    Name = $Breach.Name
                    Date = if ($Breach.BreachDate) { $Breach.BreachDate } else { "Unknown" }
                    DataExposed = if ($Breach.DataClasses) { ($Breach.DataClasses -join ', ') } else { "Not specified" }
                }
            }
            
            $breachResult.BreachCount = $BreachDetails.Count
            $breachResult.Breaches = $BreachDetails
            $breachResult.Status = "Breached"
        } else {
            Write-Host "  [OK] No breaches found" -ForegroundColor Green
            $breachResult.Status = "Clean"
        }

    } catch {
        Write-Host "  [ERROR] Checking $Email : $($_.Exception.Message)" -ForegroundColor Red
        $breachResult.Status = "Error"
    }
    
    $breachResults += $breachResult
}

Write-Host "`nBreach check complete!" -ForegroundColor Green

#endregion

#region Generate Reports

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Generating Reports" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Generate HTML Report
$Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$FilenameTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutputDir = $PSScriptRoot
$HtmlFile = Join-Path $OutputDir "breach-report-$FilenameTimestamp.html"
$TotalBreaches = ($breachResults | ForEach-Object { $_.BreachCount } | Measure-Object -Sum).Sum
$BreachedAccountsList = @($breachResults | Where-Object { $_.BreachCount -gt 0 })
$BreachedAccounts = $BreachedAccountsList.Count

# Use the stored group names (collected before disconnecting from Graph)
$GroupNamesList = if ($script:ProcessedGroupNames) { $script:ProcessedGroupNames -join ', ' } else { "N/A" }

$HtmlHead = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Security Breach Report - imab.dk</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: #f5f5f5;
            padding: 40px 20px;
            line-height: 1.6;
            color: #333;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            border-radius: 4px;
            overflow: hidden;
        }
        .header {
            background: #222222;
            color: white;
            padding: 40px 40px 30px 40px;
            border-bottom: 3px solid #0078d4;
        }
        .brand-name {
            font-size: 80px;
            font-weight: 700;
            margin-bottom: 5px;
            letter-spacing: -0.5px;
            color: #ffffff;
        }
        .tagline {
            font-size: 18px;
            color: #5eaff7;
            margin-bottom: 25px;
            font-weight: 300;
        }
        .report-title {
            font-size: 36px;
            font-weight: 300;
            margin-top: 20px;
            margin-bottom: 8px;
            color: #ffffff;
        }
        .report-tenant {
            font-size: 15px;
            color: #999999;
            font-weight: 300;
            margin-bottom: 5px;
        }
        .report-subtitle {
            font-size: 16px;
            color: #cccccc;
            font-weight: 300;
        }
        .data-source {
            font-size: 12px;
            color: #999999;
            font-weight: 300;
            margin-top: 5px;
            font-style: italic;
        }
        .content {
            padding: 40px;
        }
        .disclaimer {
            background: #fff8e1;
            border-left: 3px solid #ffc107;
            padding: 15px 20px;
            margin-bottom: 30px;
            border-radius: 2px;
            font-size: 15px;
            color: #666;
            line-height: 1.6;
        }
        .disclaimer strong {
            color: #333;
            font-weight: 500;
        }
        .summary {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 40px;
        }
        .summary-card {
            background: #fafafa;
            padding: 25px;
            border-radius: 2px;
            border-left: 3px solid #0078d4;
        }
        .summary-card.danger {
            border-left-color: #d32f2f;
        }
        .summary-card.success {
            border-left-color: #388e3c;
        }
        .summary-card.info {
            border-left-color: #0078d4;
        }
        .summary-label {
            font-size: 12px;
            color: #222222;
            text-transform: uppercase;
            letter-spacing: 1px;
            margin-bottom: 8px;
            font-weight: 500;
        }
        .summary-value {
            font-size: 36px;
            font-weight: 300;
            color: #333;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            font-size: 16px;
        }
        thead {
            background: #fafafa;
            border-bottom: 2px solid #e0e0e0;
        }
        th {
            padding: 15px;
            text-align: left;
            font-weight: 500;
            text-transform: uppercase;
            font-size: 12px;
            letter-spacing: 1px;
            color: #ffffff;
            background: #222222;
        }
        td {
            padding: 15px;
            border-bottom: 1px solid #f0f0f0;
        }
        tr:last-child td {
            border-bottom: none;
        }
        .email-row {
            cursor: pointer;
            transition: background-color 0.2s;
        }
        .email-row:nth-child(even) {
            background-color: #f9f9f9;
        }
        .email-row:hover {
            background-color: #e8f4f8;
        }
        .breach-details {
            display: none;
            background: #fafafa;
        }
        .breach-details td {
            padding: 20px 15px;
        }
        .breach-item {
            background: white;
            padding: 20px;
            margin-bottom: 12px;
            border-left: 3px solid #d32f2f;
            border-radius: 2px;
        }
        .breach-name {
            font-weight: 500;
            color: #d32f2f;
            font-size: 17px;
            margin-bottom: 8px;
        }
        .breach-date {
            color: #999;
            font-size: 14px;
            margin-bottom: 10px;
        }
        .breach-data {
            color: #666;
            font-size: 15px;
            line-height: 1.6;
        }
        .expand-icon {
            float: right;
            transition: transform 0.3s;
            color: #999;
        }
        .expanded .expand-icon {
            transform: rotate(180deg);
        }
        .department-header {
            background-color: #fafafa;
            font-weight: 500;
        }
        .footer {
            background: #fafafa;
            padding: 30px 40px;
            border-top: 1px solid #e0e0e0;
            color: #666;
            font-size: 14px;
            line-height: 1.8;
        }
        .footer-section {
            margin-bottom: 15px;
        }
        .footer-title {
            font-weight: 500;
            color: #333;
            margin-bottom: 5px;
            font-size: 15px;
        }
        .footer a {
            color: #0078d4;
            text-decoration: none;
        }
        .footer a:hover {
            text-decoration: underline;
        }
        .contact-info {
            margin-top: 20px;
            padding-top: 20px;
            border-top: 1px solid #e0e0e0;
            font-size: 13px;
        }
    </style>
    <script>
        function toggleBreaches(emailId) {
            var row = document.getElementById('breach-' + emailId);
            var emailRow = document.getElementById('email-' + emailId);
            if (row.style.display === 'none' || row.style.display === '') {
                row.style.display = 'table-row';
                emailRow.classList.add('expanded');
            } else {
                row.style.display = 'none';
                emailRow.classList.remove('expanded');
            }
        }
    </script>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="brand-name">imab.dk</div>
            <div class="tagline">Everything can be done automatically, as long as you configure it manually :-)</div>
            <div class="report-title">Have I Been Pwned - Data Breach Report</div>
            <div class="report-tenant">Entra ID Tenant: $($script:TenantName)</div>
            <div class="report-subtitle">Entra ID Groups: $GroupNamesList</div>
        </div>
        <div class="content">
            <div class="disclaimer">
                <strong>Disclaimer:</strong> This security assessment report was generated using a custom PowerShell script by imab.dk, 
                utilizing the Have I Been Pwned API for data breach verification. This is not an official 
                Have I Been Pwned product. The information contained herein is confidential and intended 
                for security assessment purposes only.
            </div>
            <div class="summary">
                <div class="summary-card info">
                    <div class="summary-label">Generated</div>
                    <div class="summary-value" style="font-size: 16px;">$Timestamp</div>
                </div>
                <div class="summary-card info">
                    <div class="summary-label">Groups Checked</div>
                    <div class="summary-value" style="font-size: 16px;">$($script:ProcessedGroupNames.Count)</div>
                </div>
                <div class="summary-card">
                    <div class="summary-label">Emails Checked</div>
                    <div class="summary-value">$($usersToCheck.Count)</div>
                </div>
                <div class="summary-card danger">
                    <div class="summary-label">Total Breaches</div>
                    <div class="summary-value">$TotalBreaches</div>
                </div>
                <div class="summary-card $(if ($BreachedAccounts -eq 0) { 'success' } else { 'danger' })">
                    <div class="summary-label">Accounts Compromised</div>
                    <div class="summary-value">$BreachedAccounts</div>
                </div>
            </div>
            <table>
                <thead>
                    <tr>
                        <th>Email Address</th>
                        <th style="width: 200px;">Status</th>
                    </tr>
                </thead>
                <tbody>
"@

# Sort emails: First by Department (alphabetically), then by breach count (descending), then by email
$SortedResults = $breachResults | Sort-Object -Property Department, @{Expression={$_.BreachCount}; Descending=$true}, Email

$HtmlBody = ""
$counter = 0
$currentDepartment = ""

foreach ($Result in $SortedResults) {
    $counter++
    
    # Add department header row if we're starting a new department
    if ($Result.Department -ne $currentDepartment) {
        $currentDepartment = $Result.Department
        $HtmlBody += @"
            <tr class="department-header">
                <td colspan="2" style="padding: 12px 15px; font-size: 13px; color: #666;">
                    $currentDepartment
                </td>
            </tr>
"@
    }
    
    if ($Result.BreachCount -gt 0) {
        # Email with breaches - make it expandable
        $displayText = if ($Result.DisplayName -and $Result.DisplayName -ne $Result.Email) {
            "$($Result.DisplayName) &lt;$($Result.Email)&gt;"
        } else {
            $Result.Email
        }
        $HtmlBody += @"
            <tr id="email-$counter" class="email-row" onclick="toggleBreaches($counter)">
                <td>$displayText <span class="expand-icon">&#9660;</span></td>
                <td style="color: #d32f2f; font-weight: 500;">$($Result.BreachCount) breach(es)</td>
            </tr>
            <tr id="breach-$counter" class="breach-details">
                <td colspan="2">
"@
        foreach ($Breach in $Result.Breaches) {
            $HtmlBody += @"
                    <div class="breach-item">
                        <div class="breach-name">$($Breach.Name)</div>
                        <div class="breach-date">Date: $($Breach.Date)</div>
                        <div class="breach-data">Data Exposed: $($Breach.DataExposed)</div>
                    </div>
"@
        }
        $HtmlBody += @"
                </td>
            </tr>
"@
    } else {
        # Email with no breaches - just show the status
        $statusColor = if ($Result.Status -eq "Clean") { "#388e3c" } elseif ($Result.Status -eq "Error") { "#ff9800" } else { "#999" }
        $statusText = if ($Result.Status -eq "Clean") { "No breaches" } elseif ($Result.Status -eq "Error") { "Error checking" } else { "0" }
        $displayText = if ($Result.DisplayName -and $Result.DisplayName -ne $Result.Email) {
            "$($Result.DisplayName) &lt;$($Result.Email)&gt;"
        } else {
            $Result.Email
        }
        $HtmlBody += @"
            <tr>
                <td>$displayText</td>
                <td style="color: $statusColor; font-weight: 500;">$statusText</td>
            </tr>
"@
    }
}

$HtmlFoot = @"
                </tbody>
            </table>
        </div>
        <div class="footer">
            <div class="footer-section">
                <div class="footer-title">About This Report</div>
                <div>This security assessment report was automatically generated by imab.dk using custom PowerShell automation.</div>
            </div>
            <div class="footer-section">
                <div class="footer-title">Technology Stack</div>
                <div>PowerShell | Microsoft Graph API | Have I Been Pwned API</div>
            </div>
            <div class="footer-section">
                <div class="footer-title">Data Source</div>
                <div>Breach data provided by <a href="https://haveibeenpwned.com/" target="_blank">Have I Been Pwned</a> - This report uses publicly available breach data for security assessment purposes only.</div>
            </div>
            <div class="contact-info">
                <strong>imab.dk</strong> | Security & Identity Management Solutions<br>
                <a href="https://www.imab.dk" target="_blank">https://www.imab.dk</a><br>
                <em>Confidential - For Authorized Use Only</em>
            </div>
        </div>
    </div>
</body>
</html>
"@

$HtmlContent = $HtmlHead + $HtmlBody + $HtmlFoot

# Use UTF8 encoding without BOM for better browser compatibility
$Utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($HtmlFile, $HtmlContent, $Utf8NoBom)

Write-Host "HTML report saved to: $HtmlFile" -ForegroundColor Green

# Generate PDF from HTML (only if -GeneratePdf switch is provided)
if ($GeneratePdf) {
    $PdfFile = Join-Path $OutputDir "breach-report-$FilenameTimestamp.pdf"

    Write-Host "Generating PDF report..." -ForegroundColor Cyan

    # Try to find Chrome or Edge for PDF generation
    $chromePaths = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )

    $browserPath = $null
    $browserName = ""
    foreach ($path in $chromePaths) {
        if (Test-Path $path) {
            $browserPath = $path
            $browserName = if ($path -like "*chrome*") { "Chrome" } else { "Edge" }
            Write-Host "Found $browserName at: $path" -ForegroundColor Cyan
            break
        }
    }

    if ($browserPath) {
        try {
            # Prepare the file URI for the HTML file
            $fileUri = "file:///$($HtmlFile.Replace('\', '/'))"
            
            Write-Host "Running $browserName in headless mode..." -ForegroundColor Cyan
            
            # Create a temporary user data directory for headless mode
            $tempUserDataDir = Join-Path $env:TEMP "EdgePdfGen_$([guid]::NewGuid().ToString())"
            
            # Build argument list as single string for proper parsing
            $argumentString = "--headless=new --disable-gpu --no-sandbox --disable-dev-shm-usage --user-data-dir=`"$tempUserDataDir`" --print-to-pdf=`"$PdfFile`" `"$fileUri`""
            
            $processInfo = New-Object System.Diagnostics.ProcessStartInfo
            $processInfo.FileName = $browserPath
            $processInfo.Arguments = $argumentString
            $processInfo.RedirectStandardOutput = $true
            $processInfo.RedirectStandardError = $true
            $processInfo.UseShellExecute = $false
            $processInfo.CreateNoWindow = $true
            
            $process = New-Object System.Diagnostics.Process
            $process.StartInfo = $processInfo
            $process.Start() | Out-Null
            
            # Read stdout to prevent process blocking (output buffer must be consumed)
            $process.StandardOutput.ReadToEnd() | Out-Null
            $stderr = $process.StandardError.ReadToEnd()
            $process.WaitForExit()
            
            # Clean up temporary user data directory
            if (Test-Path $tempUserDataDir) {
                try {
                    Remove-Item -Path $tempUserDataDir -Recurse -Force -ErrorAction SilentlyContinue
                } catch {
                    # Ignore cleanup errors
                }
            }
            
            # Check if PDF was created
            if (Test-Path $PdfFile) {
                Write-Host "PDF report saved to: $PdfFile" -ForegroundColor Green
            } else {
                Write-Host "Failed to generate PDF." -ForegroundColor Yellow
                if ($stderr) {
                    Write-Host "Error details: $stderr" -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "Error generating PDF: $_" -ForegroundColor Yellow
            Write-Host "HTML report is still available at: $HtmlFile" -ForegroundColor Cyan
        }
    } else {
        Write-Host "Chrome or Edge not found. PDF generation skipped." -ForegroundColor Yellow
        Write-Host "Install Chrome or Edge to enable PDF export." -ForegroundColor Yellow
        Write-Host "HTML report is available at: $HtmlFile" -ForegroundColor Cyan
    }
}

#endregion

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Processing Complete!" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Groups processed: $($GroupIdsToProcess.Count)" -ForegroundColor Green
Write-Host "  Users checked: $($usersToCheck.Count)" -ForegroundColor Green
Write-Host "  Breached accounts: $BreachedAccounts" -ForegroundColor $(if ($BreachedAccounts -eq 0) { 'Green' } else { 'Red' })
Write-Host "  Total breaches: $TotalBreaches" -ForegroundColor $(if ($TotalBreaches -eq 0) { 'Green' } else { 'Red' })
Write-Host "`nReports generated in: $OutputDir" -ForegroundColor Cyan
