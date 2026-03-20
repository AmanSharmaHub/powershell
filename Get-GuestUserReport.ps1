# Import Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "AuditLog.Read.All" -NoWelcome

try {
    # Get all guest users
    Write-Host "Retrieving guest users..." -ForegroundColor Cyan
    try {
        $guestUsers = Get-MgUser -All `
            -Filter "userType eq 'Guest'" `
            -Property "Id,DisplayName,UserPrincipalName,Mail,AccountEnabled,CreatedDateTime,ExternalUserState,ExternalUserStateChangeDateTime,SignInActivity" `
            -ErrorAction Stop
        Write-Host "Found $($guestUsers.Count) guest user(s)."
    }
    catch {
        Write-Host "Error retrieving guest users: $_" -ForegroundColor Red
        exit
    }

    if ($guestUsers.Count -eq 0) {
        Write-Host "No guest users found in this tenant." -ForegroundColor Yellow
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $counter  = 0

    foreach ($guest in $guestUsers) {
        $counter++
        Write-Progress -Activity "Processing guest users" -Status "$counter of $($guestUsers.Count): $($guest.DisplayName)" `
            -PercentComplete (($counter / $guestUsers.Count) * 100)

        $lastSignIn = if ($guest.SignInActivity.LastSignInDateTime) {
            $guest.SignInActivity.LastSignInDateTime.ToString('yyyy-MM-dd')
        } else { "Never / not available" }

        $inviteStatus = if ($guest.ExternalUserState) {
            $guest.ExternalUserState
        } else { "Unknown" }

        $inviteStatusChanged = if ($guest.ExternalUserStateChangeDateTime) {
            $guest.ExternalUserStateChangeDateTime.ToString('yyyy-MM-dd')
        } else { "N/A" }

        $results.Add([PSCustomObject]@{
            "Display Name"          = $guest.DisplayName
            "UPN"                   = $guest.UserPrincipalName
            "Email"                 = $guest.Mail
            "Account Enabled"       = $guest.AccountEnabled
            "Created Date"          = $guest.CreatedDateTime.ToString('yyyy-MM-dd')
            "Invite Status"         = $inviteStatus
            "Invite Status Changed" = $inviteStatusChanged
            "Last Sign In"          = $lastSignIn
        })
    }

    Write-Progress -Activity "Processing guest users" -Completed

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\GuestUserReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total guest users reported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
