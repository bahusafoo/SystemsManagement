############################################
# Secure-ExchangeOnlineMailboxes.ps1
# Author(s): Sean Huggans
$ScriptVersion = "23.10.2.4"
############################################
# Script helps identify and resolve issues
# created from compromised access in exchange
# online.
###########################################
Install-Module -Name ExchangeOnlineManagement -RequiredVersion 3.3.0 -force

Import-Module ExchangeOnlineManagement

Connect-ExchangeOnline

Set-OrganizationConfig -MailTipsExternalRecipientsTipsEnabled $true

Get-CASMailboxPlan -Filter {ImapEnabled -eq "true" -or PopEnabled -eq "true" } | set-CASMailboxPlan -ImapEnabled $false -PopEnabled $false
Get-CASMailbox -Filter {ImapEnabled -eq "true" -or PopEnabled -eq "true" } | Select-Object @{n = "Identity"; e = {$_.primarysmtpaddress}} | Set-CASMailbox -ImapEnabled $false -PopEnabled $false

foreach ($SMTPEnabledMailBox in [array]$(Get-CASMailbox)) {
    Try {
        if ($SMTPEnabledMailBox.SmtpClientAuthenticationDisabled -ne $true) {
            $SMTPEnabledMailBox | Set-CASMailbox -SmtpClientAuthenticationDisabled $true -ErrorAction Stop
            Write-host "$($SMTPEnabledMailBox.Identity),Disabled"
        } else {
            Write-host "$($SMTPEnabledMailBox.Identity),AlreadyDisabled"
        }
    } catch {
        Write-host "$($SMTPEnabledMailBox.Identity),Error"
    }
}


Get-TransportRule | Where-Object {$_.RedirectMessageTo -ne $null} | ft Name,RedirectMessageTo