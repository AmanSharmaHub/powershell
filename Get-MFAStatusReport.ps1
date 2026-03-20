# Import Microsoft Graph modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Reports

# Connect to Microsoft Graph
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All", "UserAuthenticationMethod.Read.All", "AuditLog.Read.All" -NoWelcome

try {
    # Get all users
    Write-Host "Retrieving users..." -ForegroundColor Cyan
    try {
        $users = Get-MgUser -All -Property "Id,DisplayName,UserPrincipalName,AccountEnabled,SignInActivity" -ErrorAction Stop
        Write-Host "Found $($users.Count) user(s)."
    }
    catch {
        Write-Host "Error retrieving users: $_" -ForegroundColor Red
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $counter = 0

    foreach ($user in $users) {
        $counter++
        Write-Progress -Activity "Processing users" -Status "$counter of $($users.Count): $($user.DisplayName)" `
            -PercentComplete (($counter / $users.Count) * 100)

        # Get authentication methods for the user
        try {
            $authMethods = Get-MgUserAuthenticationMethod -UserId $user.Id -ErrorAction Stop

            $methodTypes = $authMethods | ForEach-Object {
                switch ($_.AdditionalProperties['@odata.type']) {
                    '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' { 'Microsoft Authenticator' }
                    '#microsoft.graph.phoneAuthenticationMethod'                  { 'Phone (SMS/Call)' }
                    '#microsoft.graph.fido2AuthenticationMethod'                  { 'FIDO2 Security Key' }
                    '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod'{ 'Windows Hello for Business' }
                    '#microsoft.graph.emailAuthenticationMethod'                  { 'Email OTP' }
                    '#microsoft.graph.passwordAuthenticationMethod'               { 'Password' }
                    '#microsoft.graph.softwareOathAuthenticationMethod'           { 'Software OATH Token' }
                    '#microsoft.graph.temporaryAccessPassAuthenticationMethod'    { 'Temporary Access Pass' }
                    default                                                        { 'Unknown method' }
                }
            }

            # MFA is considered enabled if any method beyond password is registered
            $nonPasswordMethods = $methodTypes | Where-Object { $_ -ne 'Password' }
            $mfaEnabled = if ($nonPasswordMethods) { "Enabled" } else { "Not enabled" }
            $methodList = if ($methodTypes) { $methodTypes -join "; " } else { "None" }
        }
        catch {
            Write-Host "Error retrieving auth methods for '$($user.DisplayName)': $_" -ForegroundColor Yellow
            $mfaEnabled = "Error retrieving"
            $methodList  = "Error retrieving"
        }

        $lastSignIn = if ($user.SignInActivity.LastSignInDateTime) {
            $user.SignInActivity.LastSignInDateTime
        } else { "Never / not available" }

        $results.Add([PSCustomObject]@{
            "Display Name"          = $user.DisplayName
            "UPN"                   = $user.UserPrincipalName
            "Account Enabled"       = $user.AccountEnabled
            "MFA Status"            = $mfaEnabled
            "Authentication Methods"= $methodList
            "Last Sign In"          = $lastSignIn
        })
    }

    Write-Progress -Activity "Processing users" -Completed

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\MFAStatusReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total users reported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-MgGraph | Out-Null
    Write-Host "Disconnected from Microsoft Graph."
}
