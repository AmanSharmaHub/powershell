# Import the Exchange Online module
Import-Module ExchangeOnlineManagement

# Connect to Exchange Online
Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

try {
    # Get all mailboxes
    Write-Host "Retrieving mailboxes..." -ForegroundColor Cyan
    try {
        $mailboxes = Get-Mailbox -ResultSize Unlimited -ErrorAction Stop
        Write-Host "Found $($mailboxes.Count) mailbox(es)."
    }
    catch {
        Write-Host "Error retrieving mailboxes: $_" -ForegroundColor Red
        exit
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $counter = 0

    foreach ($mailbox in $mailboxes) {
        $counter++
        Write-Progress -Activity "Processing mailboxes" -Status "$counter of $($mailboxes.Count): $($mailbox.DisplayName)" `
            -PercentComplete (($counter / $mailboxes.Count) * 100)

        # Get mailbox statistics
        try {
            $stats = Get-MailboxStatistics -Identity $mailbox.UserPrincipalName -ErrorAction Stop

            # Parse total item size to MB
            $sizeString = $stats.TotalItemSize.ToString()
            $sizeMB = if ($sizeString -match '([\d,]+) bytes') {
                [math]::Round([int64]($matches[1] -replace ',', '') / 1MB, 2)
            } else { "Unknown" }

            # Parse quota values
            $issueWarning  = if ($mailbox.IssueWarningQuota  -ne 'Unlimited') { $mailbox.IssueWarningQuota  } else { "Unlimited" }
            $prohibitSend  = if ($mailbox.ProhibitSendQuota  -ne 'Unlimited') { $mailbox.ProhibitSendQuota  } else { "Unlimited" }
            $prohibitAll   = if ($mailbox.ProhibitSendReceiveQuota -ne 'Unlimited') { $mailbox.ProhibitSendReceiveQuota } else { "Unlimited" }

            $results.Add([PSCustomObject]@{
                "Display Name"              = $mailbox.DisplayName
                "UPN"                       = $mailbox.UserPrincipalName
                "Mailbox Type"              = $mailbox.RecipientTypeDetails
                "Total Size (MB)"           = $sizeMB
                "Item Count"                = $stats.ItemCount
                "Deleted Item Count"        = $stats.DeletedItemCount
                "Issue Warning Quota"       = $issueWarning
                "Prohibit Send Quota"       = $prohibitSend
                "Prohibit Send/Receive"     = $prohibitAll
                "Last Logon Time"           = $stats.LastLogonTime
            })
        }
        catch {
            Write-Host "Error retrieving stats for '$($mailbox.DisplayName)': $_" -ForegroundColor Yellow
        }
    }

    Write-Progress -Activity "Processing mailboxes" -Completed

    if ($results.Count -eq 0) {
        Write-Host "No mailbox statistics could be retrieved." -ForegroundColor Yellow
        exit
    }

    # Export to CSV
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $outputPath = Join-Path $env:USERPROFILE "Desktop\MailboxSizeReport_$timestamp.csv"

    try {
        $results | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8
        Write-Host "Report exported to: $outputPath" -ForegroundColor Green
        Write-Host "Total mailboxes reported: $($results.Count)"
    }
    catch {
        Write-Host "Error exporting to CSV: $_" -ForegroundColor Red
    }
}
finally {
    Disconnect-ExchangeOnline -Confirm:$false | Out-Null
    Write-Host "Disconnected from Exchange Online."
}
