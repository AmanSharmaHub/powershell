# Entra ID Group Membership Report

A PowerShell script that queries Microsoft Entra ID (formerly Azure AD) via the Microsoft Graph API and exports a user's group memberships — including group owners and members — to a CSV report.

---

## What it does

Given a User Principal Name (UPN), the script:

1. Connects to Microsoft Graph using delegated permissions
2. Looks up the user and retrieves all groups they belong to
3. For each group, collects the group name, owners, and full member list
4. Exports the results to a CSV file on the desktop

---

## Tech stack

- PowerShell
- Microsoft Graph API
- Microsoft.Graph PowerShell SDK (`Microsoft.Graph.Authentication`, `Microsoft.Graph.Groups`, `Microsoft.Graph.Users`)

---

## Prerequisites

- PowerShell 5.1 or later
- Microsoft Graph PowerShell SDK installed:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- An account with permission to consent to the following delegated scopes:
  - `User.Read.All`
  - `Group.Read.All`

> These scopes typically require admin consent in your tenant.

---

## Usage

```powershell
.\Get-EntraIDGroupReport.ps1
```

You will be prompted to sign in to Microsoft Graph and enter the target user's UPN. The report is saved to your desktop as:

```
EntraID_GroupReport_username_domain_com.csv
```

---

## Output

| Column | Description |
|---|---|
| Name of the Group | Display name of the group |
| Group Owner | Semicolon-separated list of owner display names |
| Members | Semicolon-separated list of member display names |
