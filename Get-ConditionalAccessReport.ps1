# Import Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Identity.SignIns

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Policy.Read.All" -NoWelcome

try {
    # Get all Conditional Access policies
    Write-Host "Retrieving Conditional Access policies..." -ForegroundColor Cyan
    try {
        $policies = Get-MgIdentityConditionalAccessPolicy -All -ErrorAction Stop
        Write-Host "Found $($policies.Count) policy/policies."
    }
    catch {
        Write-Host "Error retrieving Conditional Access policies: $_" -ForegroundColor Red
        exit
    }

    if ($policies.Count -eq 0) {
        Write-Host "No Conditional Access policies found." -ForegroundColor Yellow
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($policy in $policies) {
        # Included users
        $includedUsers = if ($policy.Conditions.Users.IncludeUsers) {
            $policy.Conditions.Users.IncludeUsers -join "; "
        } else { "None" }

        # Excluded users
        $excludedUsers = if ($policy.Conditions.Users.ExcludeUsers) {
            $policy.Conditions.Users.ExcludeUsers -join "; "
        } else { "None" }

        # Included groups
        $includedGroups = if ($policy.Conditions.Users.IncludeGroups) {
            $policy.Conditions.Users.IncludeGroups -join "; "
        } else { "None" }

        # Excluded groups
        $excludedGroups = if ($policy.Conditions.Users.ExcludeGroups) {
            $policy.Conditions.Users.ExcludeGroups -join "; "
        } else { "None" }

        # Included applications
        $includedApps = if ($policy.Conditions.Applications.IncludeApplications) {
            $policy.Conditions.Applications.IncludeApplications -join "; "
        } else { "None" }

        # Grant controls
        $grantControls = if ($policy.GrantControls.BuiltInControls) {
            $policy.GrantControls.BuiltInControls -join "; "
        } else { "None" }

        # Operator
        $operator = if ($policy.GrantControls.Operator) {
            $policy.GrantControls.Operator
        } else { "N/A" }

        # Platforms
        $platforms = if ($policy.Conditions.Platforms.IncludePlatforms) {
            $policy.Conditions.Platforms.IncludePlatforms -join "; "
        } else { "Any" }

        # Locations
        $includedLocations = if ($policy.Conditions.Locations.IncludeLocations) {
            $policy.Conditions.Locations.IncludeLocations -join "; "
        } else { "Any" }

        $results.Add([PSCustomObject]@{
            "Policy Name"        = $policy.DisplayName
            "State"              = $policy.State
            "Created"            = $policy.CreatedDateTime
            "Modified"           = $policy.ModifiedDateTime
            "Included Users"     = $includedUsers
            "Excluded Users"     = $excludedUsers
            "Included Groups"    = $includedGroups
            "Excluded Groups"    = $excludedGroups
            "Included Apps"      = $includedApps
            "Platforms"          = $platforms
            "Locations"          = $includedLocations
            "Grant Controls"     = $grantControls
            "Grant Operator"     = $operator
        })
    }

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\ConditionalAccessReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total policies reported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
