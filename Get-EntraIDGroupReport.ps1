# Import the Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph with required scopes
Connect-MgGraph -Scopes "User.Read.All", "Group.Read.All" -NoWelcome

try {
    # Prompt for the user's email or UPN with basic validation
    do {
        $userUPN = Read-Host "Enter the user's email or User Principal Name (UPN)"
        if ([string]::IsNullOrWhiteSpace($userUPN)) {
            Write-Host "UPN cannot be empty. Please try again." -ForegroundColor Yellow
        }
    } while ([string]::IsNullOrWhiteSpace($userUPN))

    # Get the user object
    try {
        $user = Get-MgUser -Filter "userPrincipalName eq '$userUPN'" `
            -Property "Id,DisplayName,UserPrincipalName" -ErrorAction Stop

        if (-not $user) {
            Write-Host "User '$userUPN' not found." -ForegroundColor Red
            exit
        }
        Write-Host "Found user: $($user.DisplayName) ($($user.UserPrincipalName))"
    }
    catch {
        Write-Host "Error retrieving user: $_" -ForegroundColor Red
        exit
    }

    # Get the groups the user is a member of
    try {
        $groups = Get-MgUserMemberOf -UserId $user.Id -All |
            Where-Object { $_.AdditionalProperties['@odata.type'] -eq '#microsoft.graph.group' }

        if ($groups.Count -eq 0) {
            Write-Host "User is not a member of any groups." -ForegroundColor Yellow
            exit
        }

        Write-Host "Found $($groups.Count) groups for the user."
    }
    catch {
        Write-Host "Error retrieving groups: $_" -ForegroundColor Red
        exit
    }

    # Use a generic list to avoid array recreation on each iteration
    $results = [System.Collections.Generic.List[object]]::new()

    # Iterate through each group
    foreach ($group in $groups) {
        $groupId = $group.Id
        $groupDetails = Get-MgGroup -GroupId $groupId -Property "Id,DisplayName"

        Write-Host "Processing group: $($groupDetails.DisplayName)"

        # Get group owners — use AdditionalProperties to avoid per-user API calls
        try {
            $owners = Get-MgGroupOwner -GroupId $groupId -All -Property "DisplayName"
            $ownerNames = ($owners | ForEach-Object {
                $_.AdditionalProperties['displayName']
            }) -join "; "
            if ([string]::IsNullOrWhiteSpace($ownerNames)) { $ownerNames = "No owners found" }
        }
        catch {
            Write-Host "Error retrieving owners for group '$($groupDetails.DisplayName)': $_" -ForegroundColor Yellow
            $ownerNames = "Error retrieving owners"
        }

        # Get group members — use AdditionalProperties to avoid per-user API calls
        try {
            $members = Get-MgGroupMember -GroupId $groupId -All -Property "DisplayName"
            $memberNames = ($members | ForEach-Object {
                $_.AdditionalProperties['displayName']
            }) -join "; "
            if ([string]::IsNullOrWhiteSpace($memberNames)) { $memberNames = "No members found" }
        }
        catch {
            Write-Host "Error retrieving members for group '$($groupDetails.DisplayName)': $_" -ForegroundColor Yellow
            $memberNames = "Error retrieving members"
        }

        # Add result to list
        $results.Add([PSCustomObject]@{
            "Name of the Group" = $groupDetails.DisplayName
            "Group Owner"       = $ownerNames
            "Members"           = $memberNames
        })
    }

    # Build a portable output path — saves to the user's desktop
    $safeUPN = $userUPN.Replace('@', '_').Replace('.', '_')
    $outputPath = Join-Path $env:USERPROFILE "Desktop\EntraID_GroupReport_$safeUPN.csv"

    # Export results to CSV
    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    # Always disconnect, even if the script exits early
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
