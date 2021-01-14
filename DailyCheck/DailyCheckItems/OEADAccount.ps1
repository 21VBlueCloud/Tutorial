#####################################################################################
#
#File: OEADAccount.ps1
#Author: Wende SONG (Wind)
#Version: 1.0
#
##  Revision History:
##  Date       Version    Alias       Reason for change
##  --------   -------   --------    ---------------------------------------
##  9/19/2016   1.0       Wind        First version.
##                                    
##  3/13/2018   1.1       Wind        Add OE accounts to check.
##
#####################################################################################

<#
.SYNOPSIS

.DESCRIPTION

.PARAMETER

.EXAMPLE
PS C:\>
#>

Param (
    [Parameter(Mandatory=$true)]
    [String] $xmlConfig,
    [String[]] $Module,
    [String[]] $Helper,
    [System.Management.Automation.PSCredential] $Credential
    
)

#Pre-loading
##==============================================================================================================

# Import module
if ($Module) {
    Import-Module $Module
}

Import-Module ActiveDirectory -ErrorAction Stop

#Load helper
$helper | %{ . $_ }

#Load xml configuraion file
$Xml = New-Object -TypeName System.Xml.XmlDocument
$Xml.PreserveWhitespace = $false
$Xml.Load($XmlConfig)
$AdminSamName = $Xml.DailyCheck.OEADAccount.AdminUser
$UserSamName = $Xml.DailyCheck.OEADAccount.User
$PasswordExpireDays = $Xml.DailyCheck.OEADAccount.PasswordExpireDays -as [Int]

If ($Xml.HasChildNodes -eq $false) {
    Write-Host "Can not load config file `"$XmlConfig`"!"
    Break
}

Function SendNotificationMail {
    Param (
        [Parameter(Mandatory=$true)]
        $User,
        [Switch] $ExpiredMail,
        [Switch] $WarningMail
    )

    if ($ExpiredMail.IsPresent) {
        $Subject = "Your CHN account '{0}' has been expired!" -f $User.Account
    }

    if ($WarningMail.IsPresent) {
        $Subject = "Your CHN account '{0}' will expire in {1} days!" -f $User.Account, $User.PasswordExpireDays
    }
    
    $Content = Format-HtmlTable -Contents ($User | Select-Object DisplayName,Account,PasswordExpiredDate,PasswordLastSet,PasswordExpired)`
                 -Title "Account Info" -Cellpadding 1 -Cellspacing 1
    try {
        Send-Email -To $User.EMail -mailbody $Content -mailsubject $Subject -BodyAsHtml
        Write-Host ("Send notification mail to {0} <{1}>" -f $User.DisplayName,$user.Account) -ForegroundColor Green
    }
    catch {
        Write-Host $_
    }
}

$separator = "=" * $Host.UI.RawUI.WindowSize.Width

# Initialize HTML table
#$HtmlBody = "<TABLE Class='OEADACCOUNT' border='1' cellpadding='0'cellspacing='0' style='Width:900px'>"
##===============================================================================================================

# Main code

# header
#$TableHeader = "OE Account Expiration List"
#$HtmlBody += "<TR style=background-color:#0066CC;font-weight:bold;font-size:17px><TD colspan='6' align='center' style=color:#FAF4FF>"`
#            + $TableHeader`
#            + "</TD></TR>"`

# Get max password age
$PasswordPolicy = Get-ADDefaultDomainPasswordPolicy
$maxage = $PasswordPolicy.MaxPasswordAge
$Today = Get-Date

$RecordFullPath = $xml.DailyCheck.OEADAccount.CsvFullPath
if (!(Test-Path $RecordFullPath)) {
    Write-Host "Cannot find '$RecordFullPath'! Create it." -ForegroundColor Yellow
    try {
        New-Item $RecordFullPath -ItemType File -ErrorAction Stop | Out-Null
        Write-Host "Creation done." -ForegroundColor Green
    }
    catch {
        Write-Host "Cannot create file '$RecordFullPath'!" -ForegroundColor Red
    }
}

$Records = Import-Csv $RecordFullPath
$TodayRecords = GetTodayRecord $Records

if (!$TodayRecords) {

    # get admin and user account
    $adminou = "OU=People,OU=Admins,DC=CHN,DC=SPONETWORK,DC=COM"
    $userou = "OU=Employees,OU=People,DC=CHN,DC=SPONETWORK,DC=COM"
    $filter = "Enabled -eq 'True'"
    $AdminUsers = @(Get-ADUser -SearchBase $adminou -Filter $filter -Properties *) | ?{$_.SamAccountName -in $AdminSamName}
    $Users = @(Get-ADUser -SearchBase $userou -Filter $filter -Properties *) | ?{$_.SamAccountName -in $UserSamName}

    if (!$AdminUsers -and !$Users) {
        Write-Host "Cannot find OE account!" -ForegroundColor Red
        Break
    }

    # find out accounts which will expire and expired!
    $WarningUsers = @()
    $ExpiredUsers  = @()

    $Users += $AdminUsers
    
    foreach ($u in $Users) {
        $PasswordExpiredDate = $u.PasswordLastSet + $maxage
        $days = ($PasswordExpiredDate - $Today).totalDays -as [Int]
        $properties = @{DisplayName=$u.DisplayName
                        Account=$u.SamAccountName
                        Email=$u.mail
                        PasswordLastSet=$u.PasswordLastSet
                        PasswordExpiredDate=$PasswordExpiredDate
                        PasswordExpireDays=$days
                        PasswordExpired=$u.PasswordExpired}
        $obj = New-Object -TypeName PSObject -Property $properties

        if ($obj.PasswordExpired) {
            Write-Host "User `"$($obj.DisplayName)`" password has been expired!" -ForegroundColor Red
            $ExpiredUsers += $obj
            continue
        }

        if ($obj.PasswordExpireDays -lt $PasswordExpireDays) {
            Write-Host "User `"$($obj.DisplayName)`" will expire in $($obj.PasswordExpireDays)!" -ForegroundColor Yellow
            $WarningUsers += $obj
        }
    }

    foreach ($u in $ExpiredUsers) {
        SendNotificationMail -User $u -ExpiredMail
    }

    foreach ($u in $WarningUsers) {
        SendNotificationMail -User $u -WarningMail
    }

    $Date = Get-Date
    $Properties = @{
        DateTime = $Date
        Check = "Done"
    }
    $record = New-Object -TypeName PSObject -Property $properties
    AddRecord -InputObject $record -CsvFullPath $RecordFullPath

}
else {
    Write-Host "No need to check due to it had done today!" -ForegroundColor Yellow
}

Write-Host "Checking for 'OEADAccount' done!" -ForegroundColor Green
Write-Host $separator

# Post process
##===============================================================================================================
# $HtmlBody += "</table>"

# return $HtmlBody
#$HtmlBody | Out-File .\test.html
#Start .\test.html
##===============================================================================================================
