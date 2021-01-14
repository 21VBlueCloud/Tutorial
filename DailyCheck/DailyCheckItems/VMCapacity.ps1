#####################################################################################
#
#File: VMCapacity.ps1
#Author: Wende SONG (Wind)
#Version: 1.0
#
##  Revision History:
##  Date       Version    Alias       Reason for change
##  --------   -------   --------    ---------------------------------------
##  9/19/2016   1.0       Wind        First version.
##                                    
##
##  7/10/2018   1.2       Wind        Bug fix:
##                                      Update function  GetLastdayRecord due to it
##                                      cannot find the right last day records.
##
##  9/17/2018   1.3       Wind        Add new record for DR farm.
##                                    Just simple show for DR warning if VM count different
##                                    with PR.
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


#Load helper
$helper | %{ . $_ }

# function

#Load xml configuraion file
$Xml = New-Object -TypeName System.Xml.XmlDocument
$Xml.PreserveWhitespace = $false
$Xml.Load($XmlConfig)

If ($Xml.HasChildNodes -eq $false) {
    Write-Host "Can not load config file `"$XmlConfig`"!"
    Break
}

$Date = Get-Date
$StorePath = $xml.DailyCheck.VMCapacity.StorePath
$GoalsPath = $xml.DailyCheck.VMCapacity.GoalsPath
$DRStorePath = $xml.DailyCheck.VMCapacity.DRStorePath
$DRGoalsPath = $xml.DailyCheck.VMCapacity.DRGoalsPath

# Create path if it's not exsit.
if (!(Test-Path $StorePath)) { 
    try {
        New-Item -Path $StorePath -Type file 
    }
    catch {
        Write-Host $_
        break
    }
}
if (!(Test-Path $GoalsPath)) { 
    try {
        New-Item -Path $GoalsPath -Type file 
    }
    catch {
        Write-Host $_
        break
    }
}

$WarningThreshold = $xml.DailyCheck.VMCapacity.Threshold.DefaultWarning
$AlertThreshold = $xml.DailyCheck.VMCapacity.Threshold.DefaultAlert

$separator = "=" * $Host.UI.RawUI.WindowSize.Width

# Initialize HTML table
$HtmlBody = "<TABLE Class='VMCAPACITY' border='1' cellpadding='0'cellspacing='0' style='Width:900px'>"

# header
$TableHeader = "Content Farm Capacity"
$HtmlBody += "<TR style=background-color:$($CommonColor['Blue']);font-weight:bold;font-size:17px><TD colspan='6' align='center' style=color:$($CommonColor['White'])>"`
             + $TableHeader + "</TD></TR>"
##===============================================================================================================

# Main code

$ContentFarmObj = Get-CenteralFarm -Role Content
$PRFarmObjs = @($ContentFarmObj | ? RecoveryFarmId -NE 0)

foreach ($PRFarmObj in $PRFarmObjs) {

$HtmlBody += "<tr><td>"
$HtmlBody += "<table border='1' cellpadding='0'cellspacing='0' style='Width:900px'>"
$HtmlBody += "<tr><td>" + "FarmLabel: " + $PRFarmObj.Label + "</tr></td>"


<#
$HtmlBody += "<TR style=background-color:#00A600;font-weight:bold;font-size:17px>`
                <TD colspan='6' align='center' style=color:#FAF4FF></TD></TR>"
#>

$DedicateFarms = @($PRFarmObj)
$PRFarmId = $PRFarmObj.FarmId


# Update 1.1: Add SQL in
$SQLFarmObj = Get-CenteralFarm -Identity $PRFarmObj.SqlFarmId
$DedicateFarms += $SQLFarmObj


## Update 1.3: DR farm
$DRFarmObj = @(Get-CenteralFarm $PRFarmObj.RecoveryFarmId)
$DRFarmId = $DRFarmObj.FarmId
$DRFarmObj += Get-CenteralFarm -Identity $DRFarmObj.SqlFarmId

# check farm goals and VMs
$PRFarmGoalObj = @($DedicateFarms | Get-CenteralFarmGoal -FarmGoalType VMRoleInstanceCount)

$GoalsHistoryObj = @(Import-Csv -Path $GoalsPath) | Where-Object FarmId -in $DedicateFarms.FarmId

# Update: 1.2
$YesterdayGoalsObj = @(GetLastdayRecord $GoalsHistoryObj)

$VMsObj = $DedicateFarms | Get-CenteralVM | ? PMachineId -gt 0
$VMsHistoryObj = @(Import-Csv -Path $StorePath) | Where-Object NetworkId -in $DedicateFarms.NetworkId

# Update: 1.2
$YesterdayVMsObj = @(GetLastdayRecord $VMsHistoryObj) 

## Update 1.3: Get DR farm info
$DRFarmGoalObj = @($DRFarmObj | Get-CenteralFarmGoal -FarmGoalType VMRoleInstanceCount)
$DRGoalHistoryObj = @(Import-Csv -Path $DRGoalsPath)
$DRYesterdayGoalsObj = @(GetLastdayRecord $DRGoalsHistoryObj)
$DRVMsObj = $DRFarmObj | Get-CenteralVM | ? PMachineId -gt 0
$DRVMsHistoryObj = @(Import-Csv -Path $DRStorePath)
$DRYesterdayVMsObj = @(GetLastdayRecord $DRVMsHistoryObj) 
$DRMessage = @()

$Roles = @($PRFarmGoalObj.Role)
$DifferenceGoalsObj = @()
$DifferenceRoleObj = @()
$CapacityObjs = @()

# To identify the PR farm is failed over or not.
if($YesterdayGoalsObj.Count -and $PRFarmId -notin $YesterdayGoalsObj.FarmId) {
    $warning = "PR farm has been failover!"
    Write-Warning $warning
    $HtmlBody += "<TR style=background-color:$($CommonColor['Red']);font-size:17px>`
                <TD colspan='6' align='center' style='color:Write'>$warning</TD></TR>"
    $failover = $true
}

foreach ($r in $Roles) {
    # for goals
    if (!$failover) { 
        $YesterdayGoalObj = $YesterdayGoalsObj | ? Role -EQ $r
        if ($YesterdayGoalObj) { $YesterdayGoal = $YesterdayGoalObj.Goal }
        else { $YesterdayGoal = 0 }
    }
    else { $YesterdayGoal = 0 }
    $currentGoalObj = $PRFarmGoalObj | ? Role -EQ $r
    $TodayGoal = $currentGoalObj.Goal
    $DifferentialGoal =$TodayGoal - $YesterdayGoal
    $DiffGoalObj = New-Object -TypeName PSObject -Property @{DateTime=$Date;FarmId=$currentGoalObj.FarmId
                                                                Role=$r;YesterdayGoal=$YesterdayGoal
                                                                TodayGoal=$TodayGoal;Increase=$DifferentialGoal}
    
    $DifferenceGoalsObj += $DiffGoalObj
    
    # for VMs
    if (!$failover) { $YesterdayRoleVMs = $($YesterdayVMsObj | ? Role -EQ $r | ? State -EQ Running) }
    else { $YesterdayRoleVMs = @() }
    $currentRoleVMs = $VMsObj | ? Role -EQ $r | ? State -EQ Running
    $YesterdayCount = $YesterdayRoleVMs.Count
    $TodayCount = $currentRoleVMs.Count
    $DifferentialRoleCount = $TodayCount - $YesterdayCount 
    $DiffRoleObj = New-Object -TypeName PSObject -Property @{DateTime=$Date;FarmId=$currentRoleVMs[0].FarmId;Role=$r
                                                                YesterdayCount=$YesterdayCount;TodayCount=$TodayCount
                                                                Increase=$DifferentialRoleCount}
    $DifferenceRoleObj += $DiffRoleObj
    
    if ($TodayCount -lt $TodayGoal) {
        $CapacityObj = New-Object -TypeName PSObject -Property @{Role=$r;Absence=$($TodayGoal-$TodayCount)
                                                                Goal=$TodayGoal;Count=$TodayCount
                                                                DateTime=$Date;FarmId=$currentGoalObj.FarmId}
        $CapacityObjs += $CapacityObj
        $NotFullCapacity = $true
    }

    ## Update 1.3: Compare PR and DR VMs and report difference.
    $DRRoleVMCount = ($DRVMsObj | ? Role -EQ $r | ? State -EQ Running).Count
    $DRTodayGoal = $DRFarmGoalObj | ? Role -eq $r | select -ExpandProperty Goal
    

    if($TodayGoal -gt $DRTodayGoal) {
        $Message = "DR goals $r [$DRTodayGoal] is less than PR [$TodayGoal]."
        $DRMessage += $Message
        Write-Host "Warning: $Message" -ForegroundColor Yellow
    }

    if($TodayCount -gt $DRRoleVMCount) {
        $Message = "DR VMs $r [$DRRoleVMCount] is less than PR [$TodayCount]."
        $DRMessage += $Message
        Write-Host "Warning: $Message" -ForegroundColor Yellow
    }    
    
    



}

# Outputs
# Show goals history comparison
$HtmlBody += "<TR style=background-color:$($CommonColor['LightBlue']);font-weight:bold;font-size:17px>`
                <TD colspan='6' align='left' style=color:$($CommonColor['White'])>Goals Comparison</TD></TR>"

$HtmlBody += "<TR style=background-color:$($CommonColor['LightGray']);font-weight:bold;font-size:17px>`
                <TD align='center'>Date</TD><TD align='center'>FarmId</TD><TD align='center'>Role</TD>`
                <TD align='center'>FormerGoal</TD><TD align='center'>TodayGoal</TD>`
                <TD align='center'>Increase</TD></TR>"

foreach ($DiffGoalObj in $DifferenceGoalsObj) {
    if ($DiffGoalObj.Increase -eq 0) { $backgroundColor = "" }
    elseif ($DiffGoalObj.Increase -lt 0) { $backgroundColor = "style=background-color:$($CommonColor['Yellow'])" }
    else { $backgroundColor = "style=background-color:$($CommonColor['Green'])" }
    $HtmlBody += "<TR style=font-size:17px>`
                <TD align='center'>$(AbstractDate $DiffGoalObj.DateTime)</TD><TD align='center'>$($DiffGoalObj.FarmId)</TD>`
                <TD align='center'>$($DiffGoalObj.Role)</TD><TD align='center'>$($DiffGoalObj.YesterdayGoal)</TD>`
                <TD align='center'>$($DiffGoalObj.TodayGoal)</TD><TD align='center' $backgroundColor>$($DiffGoalObj.Increase)</TD></TR>"
}

# Show VM count comparison
$HtmlBody += "<TR style=background-color:$($CommonColor['LightBlue']);font-weight:bold;font-size:17px>`
                <TD colspan='6' align='left' style=color:$($CommonColor['White'])>VM Count Comparison</TD></TR>"

$HtmlBody += "<TR style=background-color:$($CommonColor['LightGray']);font-weight:bold;font-size:17px>`
                <TD align='center'>Date</TD><TD align='center'>FarmId</TD><TD align='center'>Role</TD>`
                <TD align='center'>FormerCount</TD><TD align='center'>TodayCount</TD>`
                <TD align='center'>Increase</TD></TR>"

foreach ($DiffRoleObj in $DifferenceRoleObj) {
        if ($DiffRoleObj.YesterdayCount -ne 0) { $Persentage = $DiffRoleObj.TodayCount / $DiffRoleObj.YesterdayCount }
        else { $Persentage = 2 }
        if ($Persentage -eq 1) { $backgroundColor = "" }
        elseif ($Persentage -le $AlertThreshold) { $backgroundColor = "style=background-color:$($CommonColor['Red'])" }
        elseif ($Persentage -le $WarningThreshold) { $backgroundColor = "style=background-color:$($CommonColor['Yellow'])" }
        else { $backgroundColor = "style=background-color:$($CommonColor['Green'])" }
    
    $HtmlBody += "<TR style=font-size:17px>`
                <TD align='center'>$(AbstractDate $DiffRoleObj.DateTime)</TD><TD align='center'>$($DiffRoleObj.FarmId)</TD>`
                <TD align='center'>$($DiffRoleObj.Role)</TD><TD align='center'>$($DiffRoleObj.YesterdayCount)</TD>`
                <TD align='center'>$($DiffRoleObj.TodayCount)</TD><TD align='center' $backgroundColor>$($DiffRoleObj.Increase)</TD></TR>"
}

# show capacity comparison
$HtmlBody += "<TR style=background-color:$($CommonColor['LightBlue']);font-weight:bold;font-size:17px>`
                <TD colspan='6' align='left' style=color:$($CommonColor['White'])>Capacity Comparison</TD></TR>"

$HtmlBody += "<TR style=background-color:$($CommonColor['LightGray']);font-weight:bold;font-size:17px>`
                <TD align='center'>Date</TD><TD align='center'>FarmId</TD><TD align='center'>Role</TD>`
                <TD align='center'>Goal</TD><TD align='center'>Count</TD>`
                <TD align='center'>Absence</TD></TR>"

if ($NotFullCapacity) {
    foreach ($obj in $CapacityObjs) { 
        $message = "Role [$($obj.Role)] is not in full capacity running! Absent [$($obj.Absence)]"
        Write-Warning $message
        $HtmlBody += "<TR style=font-size:17px>`
                <TD align='center'>$(AbstractDate $obj.DateTime)</TD><TD align='center'>$($obj.FarmId)</TD>`
                <TD align='center'>$($obj.Role)</TD><TD align='center'>$($obj.Goal)</TD>"

        $percent = $obj.Count / $obj.Goal
        if($percent -le $WarningThreshold) {
            if($percent -gt $AlertThreshold) {
                $AlertColor = $CommonColor['Yellow']
            }
            else {
                $AlertColor = $CommonColor['Red']
            }
        }

        $HtmlBody += "<TD align='center'>$($obj.Count)</TD><TD align='center' style=background-color:$AlertColor>$($obj.Absence)</TD></TR>"

    }
}
else {
    $HtmlBody += "<TR style=font-weight:bold;font-size:17px>`
                <TD colspan='6' align='center' style=color:$($CommonColor['Green'])>Full capacity!</TD></TR>"
}


# show non-running vms
$nonRunningVMs = $VMsObj | ? State -ne "Running"
$HtmlBody += "<TR style=background-color:$($CommonColor['LightBlue']);font-weight:bold;font-size:17px>`
                <TD colspan='6' align='left' style=color:$($CommonColor['White'])>Non-running VMs</TD></TR>"

$HtmlBody += "<TR style=background-color:$($CommonColor['LightGray']);font-weight:bold;font-size:17px align='center'>`
                <TD>VMachineId</TD><TD>PMachineId</TD><TD>NetworkId</TD><TD>Role</TD><TD>Name</TD><TD>State</TD></TR>"
foreach ($vm in $nonRunningVMs) {
    $Htmlbody += "<TR style=font-size:17px align='center'>`
                    <TD>$($vm.VMachineId)</TD><TD>$($vm.PMachineId)</TD>`
                    <TD>$($vm.NetworkId)</TD><TD>$($vm.Role)</TD>`
                    <TD>$($vm.Name)</TD><TD>$($vm.State)</TD></TR>"
}
if (!$nonRunningVMs) {
    $HtmlBody += "<TR style=font-weight:bold;font-size:17px>`
                <TD colspan='6'  align='center' style=color:$($CommonColor['Green'])>None</TD></TR>"
}

## Update 1.3: Add DR message
if ($DRMessage) {
    $HtmlBody += "<TR style=font-weight:bold;font-size:17px>`
                <TD colspan='6'  align='Left' style=color:$($CommonColor['Red'])>$DRMessage</TD></TR>"
}



# add records
$GoalRecordsObj = @()
foreach ($goal in $PRFarmGoalObj) {
    $GoalRecordsObj += New-Object -TypeName PSObject -Property @{DateTime=$Date;Goal=$Goal.Goal;FarmId=$Goal.FarmId;Role=$Goal.Role}
}

if (!(GetTodayRecord -InputObject $GoalsHistoryObj)) { $GoalRecordsObj | Export-Csv $GoalsPath -Append }
else { Write-Warning "Today goals record exsit!" }

$VMRecordsObj = @()
foreach ($vm in $VMsObj) {
    $VMRecordsObj += New-Object -TypeName PSObject -Property @{DateTime=$Date;VMachineId=$vm.VMachineId
                                                                PMachineId=$vm.PMachineId;NetworkId=$vm.NetworkId
                                                                Name=$vm.Name;Role=$vm.Role
                                                                State=$vm.State;Version=$vm.Version}
}
if (!(GetTodayRecord $VMsHistoryObj)) { $VMRecordsObj | Export-Csv $StorePath -Append }
else { Write-Warning "Today capacity record exsit!" }

## Update 1.3: add DR records
$DRGoalObj = @()
foreach ($goal in $DRFarmGoalObj) {
    $DRGoalObj += New-Object -TypeName PSObject -Property @{DateTime=$Date;Goal=$Goal.Goal;FarmId=$Goal.FarmId;Role=$Goal.Role}
}

if (!(GetTodayRecord -InputObject $DRGoalHistoryObj)) { $DRGoalObj | Export-Csv $DRGoalsPath -Append }
else { Write-Warning "Today DR goals record exist!" }

$DRVMObj = @()
foreach ($vm in $DRVMsObj) {
    $DRVMObj += New-Object -TypeName PSObject -Property @{DateTime=$Date;VMachineId=$vm.VMachineId
                                                                PMachineId=$vm.PMachineId;NetworkId=$vm.NetworkId
                                                                Name=$vm.Name;Role=$vm.Role
                                                                State=$vm.State;Version=$vm.Version}
}
if (!(GetTodayRecord $DRVMsHistoryObj)) { $DRVMObj | Export-Csv $DRStorePath -Append }
else { Write-Warning "Today DR capacity record exsit!" }

## udpate 1.4
$HtmlBody += "</table>"
$HtmlBody += "</td></tr>"
}

Write-Host "Checking for 'VMCapacity' done." -ForegroundColor Green
Write-Host $separator

# Post process
##===============================================================================================================

$HtmlBody += "</table>"

return $HtmlBody
#$HtmlBody | Out-File .\test.html
#Start .\test.html
##===============================================================================================================
