# Import Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "User.ReadWrite.All", "AuditLog.Read.All" -NoWelcome

try {
    # Prompt for inactivity threshold
    do {
        $inputDays = Read-Host "Enter the number of days of inactivity to flag users (e.g. 90)"
    } while (-not ($inputDays -match '^\d+$') -or [int]$inputDays -le 0)

    $inactiveDays = [int]$inputDays
    $cutoffDate   = (Get-Date).AddDays(-$inactiveDays)

    Write-Host "Flagging users with no sign-in since: $($cutoffDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan

    # Ask for run mode
    Write-Host "`nRun mode:"
    Write-Host "  [1] Report only  — list inactive users, no changes made"
    Write-Host "  [2] Disable mode — disable each inactive user account"

    do {
        $modeInput = Read-Host "Enter 1 or 2"
    } while ($modeInput -notin @('1', '2'))

    $disableMode = $modeInput -eq '2'

    if ($disableMode) {
        Write-Host "`nDisable mode enabled. Inactive accounts will be disabled." -ForegroundColor Yellow
    } else {
        Write-Host "`nReport-only mode. No changes will be made." -ForegroundColor Cyan
    }

    # Get all enabled users with sign-in activity
    Write-Host "Retrieving users..." -ForegroundColor Cyan
    try {
        $users = Get-MgUser -All `
            -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,SignInActivity,UserType" `
            -Filter "AccountEnabled eq true" `
            -ErrorAction Stop
        Write-Host "Found $($users.Count) enabled user(s)."
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

        $lastSignIn = $user.SignInActivity.LastSignInDateTime

        # Skip users who have signed in within the threshold
        if ($lastSignIn -and $lastSignIn -gt $cutoffDate) { continue }

        $lastSignInDisplay = if ($lastSignIn) { $lastSignIn.ToString('yyyy-MM-dd') } else { "Never / not available" }
        $action = "Inactive — not disabled"

        if ($disableMode) {
            try {
                Update-MgUser -UserId $user.Id -AccountEnabled:$false -ErrorAction Stop
                $action = "Disabled"
                Write-Host "Disabled: $($user.UserPrincipalName)" -ForegroundColor Green
            }
            catch {
                $action = "Error disabling"
                Write-Host "Error disabling '$($user.UserPrincipalName)': $_" -ForegroundColor Red
            }
        }

        $results.Add([PSCustomObject]@{
            "Display Name"   = $user.DisplayName
            "UPN"            = $user.UserPrincipalName
            "User Type"      = $user.UserType
            "Last Sign In"   = $lastSignInDisplay
            "Action"         = $action
        })
    }

    Write-Progress -Activity "Processing users" -Completed

    if ($results.Count -eq 0) {
        Write-Host "No inactive users found beyond the $inactiveDays day threshold." -ForegroundColor Green
        exit
    }

    Write-Host "Found $($results.Count) inactive user(s)."

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\InactiveUsersReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
