# Import Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "Organization.Read.All" -NoWelcome

try {
    # Get all SKU display names for mapping
    Write-Host "Retrieving licence SKU information..." -ForegroundColor Cyan
    try {
        $skus = Get-MgSubscribedSku -ErrorAction Stop
        $skuMap = @{}
        foreach ($sku in $skus) {
            $skuMap[$sku.SkuId] = $sku.SkuPartNumber
        }
    }
    catch {
        Write-Host "Warning: Could not retrieve SKU names. SkuId will be used instead. $_" -ForegroundColor Yellow
        $skuMap = @{}
    }

    # Get all users with licence details
    Write-Host "Retrieving users..." -ForegroundColor Cyan
    try {
        $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,AssignedLicenses,LicenseAssignmentStates" -ErrorAction Stop
        Write-Host "Found $($users.Count) user(s)."
    }
    catch {
        Write-Host "Error retrieving users: $_" -ForegroundColor Red
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $counter  = 0

    foreach ($user in $users) {
        $counter++
        Write-Progress -Activity "Processing users" -Status "$counter of $($users.Count): $($user.DisplayName)" `
            -PercentComplete (($counter / $users.Count) * 100)

        if ($user.AssignedLicenses.Count -eq 0) {
            # Include unlicensed users for completeness
            $results.Add([PSCustomObject]@{
                "Display Name"        = $user.DisplayName
                "UPN"                 = $user.UserPrincipalName
                "Account Enabled"     = $user.AccountEnabled
                "Licence"             = "No licence assigned"
                "Assignment Type"     = "N/A"
                "Disabled Plans"      = "N/A"
            })
            continue
        }

        foreach ($licence in $user.AssignedLicenses) {
            $licenceName = if ($skuMap.ContainsKey($licence.SkuId)) {
                $skuMap[$licence.SkuId]
            } else { $licence.SkuId.ToString() }

            # Check if licence is directly assigned or via group
            $assignmentState = $user.LicenseAssignmentStates |
                Where-Object { $_.SkuId -eq $licence.SkuId } |
                Select-Object -First 1

            $assignmentType = if ($assignmentState.AssignedByGroup) {
                "Group: $($assignmentState.AssignedByGroup)"
            } else { "Direct" }

            $disabledPlans = if ($licence.DisabledPlans -and $licence.DisabledPlans.Count -gt 0) {
                $licence.DisabledPlans -join "; "
            } else { "None" }

            $results.Add([PSCustomObject]@{
                "Display Name"    = $user.DisplayName
                "UPN"             = $user.UserPrincipalName
                "Account Enabled" = $user.AccountEnabled
                "Licence"         = $licenceName
                "Assignment Type" = $assignmentType
                "Disabled Plans"  = $disabledPlans
            })
        }
    }

    Write-Progress -Activity "Processing users" -Completed

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\LicenceAssignmentReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total rows exported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
