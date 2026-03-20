# Import the Exchange Online module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

try {
    # Get all shared mailboxes
    Write-Host "Retrieving shared mailboxes..." -ForegroundColor Cyan
    try {
        $sharedMailboxes = Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -ErrorAction Stop
        Write-Host "Found $($sharedMailboxes.Count) shared mailbox(es)."
    }
    catch {
        Write-Host "Error retrieving shared mailboxes: $_" -ForegroundColor Red
        exit
    }

    if ($sharedMailboxes.Count -eq 0) {
        Write-Host "No shared mailboxes found." -ForegroundColor Yellow
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $counter = 0

    foreach ($mailbox in $sharedMailboxes) {
        $counter++
        Write-Progress -Activity "Processing shared mailboxes" -Status "$counter of $($sharedMailboxes.Count): $($mailbox.DisplayName)" `
            -PercentComplete (($counter / $sharedMailboxes.Count) * 100)

        # Get Full Access permissions
        try {
            $fullAccess = Get-MailboxPermission -Identity $mailbox.UserPrincipalName -ErrorAction Stop |
                Where-Object {
                    $_.AccessRights -contains "FullAccess" -and
                    $_.IsInherited -eq $false -and
                    $_.User -notlike "NT AUTHORITY\*"
                }
            $fullAccessUsers = if ($fullAccess) {
                ($fullAccess.User) -join "; "
            } else { "None" }
        }
        catch {
            Write-Host "Error retrieving Full Access for '$($mailbox.DisplayName)': $_" -ForegroundColor Yellow
            $fullAccessUsers = "Error retrieving"
        }

        # Get Send As permissions
        try {
            $sendAs = Get-RecipientPermission -Identity $mailbox.UserPrincipalName -ErrorAction Stop |
                Where-Object {
                    $_.AccessRights -contains "SendAs" -and
                    $_.Trustee -notlike "NT AUTHORITY\*"
                }
            $sendAsUsers = if ($sendAs) {
                ($sendAs.Trustee) -join "; "
            } else { "None" }
        }
        catch {
            Write-Host "Error retrieving Send As for '$($mailbox.DisplayName)': $_" -ForegroundColor Yellow
            $sendAsUsers = "Error retrieving"
        }

        # Get Send on Behalf permissions
        $sendOnBehalf = if ($mailbox.GrantSendOnBehalfTo) {
            ($mailbox.GrantSendOnBehalfTo) -join "; "
        } else { "None" }

        $results.Add([PSCustomObject]@{
            "Mailbox Display Name"  = $mailbox.DisplayName
            "Mailbox Email"         = $mailbox.PrimarySmtpAddress
            "Full Access"           = $fullAccessUsers
            "Send As"               = $sendAsUsers
            "Send on Behalf"        = $sendOnBehalf
        })
    }

    Write-Progress -Activity "Processing shared mailboxes" -Completed

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\SharedMailboxPermissions_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total shared mailboxes reported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Write-Host "Disconnected from Exchange Online."
}
