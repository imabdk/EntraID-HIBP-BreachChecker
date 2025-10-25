<#
.SYNOPSIS
    Gets all members of one or more Entra ID (Azure AD) groups recursively.

.DESCRIPTION
    This script retrieves all members of specified Entra ID group(s), including nested group members.
    It recursively expands nested groups to get all user members.
    Supports processing multiple groups at once.

.PARAMETER GroupId
    The Object ID(s) of the Entra ID group(s). Accepts single ID or array of IDs.

.PARAMETER GroupName
    The display name(s) of the Entra ID group(s). Accepts single name or array of names.

.PARAMETER ExpandNestedGroups
    Switch to enable recursive expansion of nested groups (default: $true).

.EXAMPLE
    .\Get-EntraIDGroupMembersRecursive.ps1 -GroupId "12345678-1234-1234-1234-123456789abc"

.EXAMPLE
    .\Get-EntraIDGroupMembersRecursive.ps1 -GroupName "IT Department"

.EXAMPLE
    .\Get-EntraIDGroupMembersRecursive.ps1 -GroupName "IT Department","Security Team","DevOps"

.EXAMPLE
    .\Get-EntraIDGroupMembersRecursive.ps1 -GroupId "12345678-1234-1234-1234-123456789abc","87654321-4321-4321-4321-cba987654321" -ExportToCsv

.NOTES
    Author: MAB
    Date: October 23, 2025
    Requires: Microsoft.Graph PowerShell module
#>

[CmdletBinding(DefaultParameterSetName = 'ById')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
    [string[]]$GroupId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ByName')]
    [string[]]$GroupName,

    [Parameter(Mandatory = $false)]
    [switch]$ExpandNestedGroups,

    [Parameter(Mandatory = $false)]
    [switch]$ExportToCsv,

    [Parameter(Mandatory = $false)]
    [string]$CsvPath = ".\EntraIDGroupMembers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# Set default behavior for ExpandNestedGroups if not explicitly specified
if (-not $PSBoundParameters.ContainsKey('ExpandNestedGroups')) {
    $ExpandNestedGroups = $true
}

# Check if Microsoft.Graph module is installed
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Groups)) {
    Write-Error "Microsoft.Graph.Groups module is not installed. Please install it using: Install-Module Microsoft.Graph.Groups -Scope CurrentUser"
    exit 1
}

if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Users)) {
    Write-Error "Microsoft.Graph.Users module is not installed. Please install it using: Install-Module Microsoft.Graph.Users -Scope CurrentUser"
    exit 1
}

# Import required modules
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
try {
    Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "Group.Read.All", "User.Read.All", "GroupMember.Read.All" -NoWelcome
    Write-Host "Successfully connected to Microsoft Graph" -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $_"
    exit 1
}

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

# Main execution
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
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "Groups processed: $($GroupIdsToProcess.Count)" -ForegroundColor Green
    Write-Host "Total members found: $($allMembers.Count)" -ForegroundColor Green
    Write-Host "  Unique Users: $(($allMembers | Where-Object { $_.Type -eq 'User' } | Select-Object -Unique ObjectId).Count)" -ForegroundColor Green
    Write-Host "  Nested Groups: $(($allMembers | Where-Object { $_.Type -eq 'Group' } | Select-Object -Unique ObjectId).Count)" -ForegroundColor Green

    # Export to CSV if requested
    if ($ExportToCsv) {
        # Filter to only users and remove duplicates based on ObjectId before exporting
        $uniqueUsers = $allMembers | Where-Object { $_.Type -eq 'User' } | Sort-Object ObjectId -Unique
        $uniqueUsers | Export-Csv -Path $CsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "`nResults exported to: $CsvPath" -ForegroundColor Green
        Write-Host "  Total unique users exported: $($uniqueUsers.Count) (groups excluded)" -ForegroundColor Green
    }

    # Display results
    Write-Host "`nDisplaying results..." -ForegroundColor Cyan
    $allMembers | Sort-Object DisplayName | Format-Table Type, DisplayName, UserPrincipalName, Department, ParentGroup, NestingLevel -AutoSize

    # Return the collection
    return $allMembers
}
catch {
    Write-Error "An error occurred: $_"
    exit 1
}
finally {
    # Disconnect from Microsoft Graph
    Write-Host "`nDisconnecting from Microsoft Graph..." -ForegroundColor Cyan
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected" -ForegroundColor Green
}
