###################################################
# Collection Evaluation Queue Monitor Script
# Author: Sean Huggans
# Version: 22.2.9.5
###################################################

$SiteCode = "FOO" # Site code 
$ProviderMachineName = "YOURSERVER.YOURDOMAIN.COM" # SMS Provider machine name
$BannerImagePath = "http://SOMESERVER.YOURDOMAIN.COM/BannerImages/Notif_GenericBanner.png"
$initParams = @{}
if((Get-Module ConfigurationManager) -eq $null) {
    Import-Module "$($ENV:SMS_ADMIN_UI_PATH)\..\ConfigurationManager.psd1" @initParams 
}
if((Get-PSDrive -Name $SiteCode -PSProvider CMSite -ErrorAction SilentlyContinue) -eq $null) {
    New-PSDrive -Name $SiteCode -PSProvider CMSite -Root $ProviderMachineName @initParams
}
Set-Location "$($SiteCode):\" @initParams

# Email:
$Script:SendingOrg = "Your Org Name Here"
$Script:FromAddress = "AccountEmail@youremaildomain.com" # Use the mailbox assigned to the account executing the scheduled task
$Script:ToAddressForAlerts = "YourToAddess@youremaildomain.com" # Address to send Alerts To
$Script:CCAddress = "YourCCAddress@youremaildomain.com" # CC Addresses for alerts
###### On-Prem SMTP Settings #########
$Script:SMTPServer= "SMTP Server"

###### Office 365 Email Settings #########
#$Script:SMTPServer = "smtp.office365.com" # O365 Settings
#$Script:smtpport = "587" # O365 Setting
#$FromPaWd = ConvertTo-SecureString -String "<Password>" -AsPlainText -force  # O365 Setting
#$script:smtpCred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $FromAddress, $FromPaWd
#$Script:FromAddress,$Script:ToAddressForITReport,$script:smtpCred,$Script:SMTPServer,$Script:smtpport

$ConfigMgrMonitoringRegKey = "HKLM:\SOFTWARE\ConfigMgr Monitoring"
if (!(Test-Path -Path $ConfigMgrMonitoringRegKey)) {
    New-Item -Path $ConfigMgrMonitoringRegKey -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
}

[array]$CollectionEvalQueueInfo = [array]$(Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption Full) + [array]$(Get-CMCollectionInfoFromEvaluationQueue -EvaluationTypeOption Manual)

Try {
    $EmailSent = Get-ItemPropertyValue -Path $ConfigMgrMonitoringRegKey -Name "ActiveAlertWithEmailSent" -ErrorAction Stop
} catch {
    $EmailSent = $false
    New-ItemProperty -Path $ConfigMgrMonitoringRegKey -PropertyType String -Name "ActiveAlertWithEmailSent" -Value $false | Out-Null
}

if ($CollectionEvalQueueInfo.Count -ge 1000) {
    if ($($EmailSent) -eq $true) {
        #Write-Host "Nothing to do, already sent notification email."
        # Do Nothing, we already sent an email about this occurrence
    } else {
        #Write-Host "Queue Greater than 1k, no email sent yet, send notification email."
        # Send Notification email
        $AlertHTML = "<html>
              <table align=""center"" style=""width:1000px"">
                <tr style=""height:100px"">
                  <td>
                    <center><img src=""$($BannerImagePath)""></center>
                    <h1 align=""center"">Collection Evaluation Queue Monitor</h1>
                  </td>
                </tr>
                <tr>
                  <td>
                    <b>Notice!  There is currently $($CollectionEvalQueueInfo.Count) collections in the collection evaluation queue.  Software deployments via deployment tools are likely taking an abnormally large amount of time.  An all-clear will be sent when this number reduces below 1000.  This alert should be treated as a seperate occurence than any previous messages.</b>
                  </td>
                </tr>
              </table>
              </html>"
        
        
        Try {
            if (($Script:CCAddress -ne "") -and ($Script:CCAddress -ne $null)) {
                Send-MailMessage -smtpServer $Script:SMTPServer -To $Script:ToAddressForAlerts -from $Script:FromAddress -Cc $Script:CCAddress -subject "Alert: Collection Evaluation Queue" -Body $AlertHTML -BodyAsHtml -ErrorAction Stop
            } else {
                Send-MailMessage -smtpServer $Script:SMTPServer -To $Script:ToAddressForAlerts -from $Script:FromAddress -subject "Alert: Collection Evaluation Queue" -Body $AlertHTML -BodyAsHtml -ErrorAction Stop
            }
           # Log-Action "Email: ""Monthly Patching Summary"", Successfully sent."
        } catch {
           # Log-Action "Email: ""Monthly Patching Summary"", Failed to send!"
        }

        # Set EmailSent registry value to true
        Set-ItemProperty -Path $ConfigMgrMonitoringRegKey -Name "ActiveAlertWithEmailSent" -Value $true | Out-Null
    }
    Write-Host ""
} else {
    if ($($EmailSent) -eq $true) {
        # Send All-Clear Email
                $AlertHTML = "<html>
              <table align=""center"" style=""width:1000px"">
                <tr style=""height:100px"">
                  <td>
                    <center><img src=""$($BannerImagePath)""></center>
                    <h1 align=""center"">Collection Evaluation Queue Monitor</h1>
                  </td>
                </tr>
                <tr>
                  <td>
                    <b>The previous collection evaluation queue count is now at $($CollectionEvalQueueInfo.Count.ToString()), which is below the configured threshhold of 1000.  A new alert will be sent if this occurs again.</b>
                  </td>
                </tr>
              </table>
              </html>"
        
        
        Try {
            if (($Script:CCAddress -ne "") -and ($Script:CCAddress -ne $null)) {
                Send-MailMessage -smtpServer $Script:SMTPServer -To $Script:ToAddressForAlerts -from $Script:FromAddress -Cc $Script:CCAddress -subject "All-Clear: Collection Evaluation Queue" -Body $AlertHTML -BodyAsHtml -ErrorAction Stop
            } else {
                Send-MailMessage -smtpServer $Script:SMTPServer -To $Script:ToAddressForAlerts -from $Script:FromAddress -subject "All-Clear: Collection Evaluation Queue" -Body $AlertHTML -BodyAsHtml -ErrorAction Stop
            }
           # Log-Action "Email: ""Monthly Patching Summary"", Successfully sent."
        } catch {
           # Log-Action "Email: ""Monthly Patching Summary"", Failed to send!"
        }

        # Set EmailSent registry value to false
        Set-ItemProperty -Path $ConfigMgrMonitoringRegKey -Name "ActiveAlertWithEmailSent" -Value $false | Out-Null
    } else {
        # Write-Host "Nothing to do, less than 1k, no email sent."
        # Do Nothing, nothing to do
    }
}
