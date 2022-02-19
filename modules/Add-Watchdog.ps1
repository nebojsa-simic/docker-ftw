. .\modules\Globals.ps1
. .\modules\Log.ps1

$existingWatchdogTask = Get-ScheduledTask | Where-Object { $_.TaskName -eq $watchdogTaskName } | Select-Object -First 1
if ($null -ne $existingWatchdogTask) {
    Unregister-ScheduledTask -TaskName "$watchdogTaskName" -Confirm:$false
}

Log -Message "Docker-FTW adding watchdog."

$watchdogHome = "$dockerFtwHome\watchdog"
New-Item -ItemType Directory -Force -Path $watchdogHome | Out-Null

$watchdogScript = "$watchdogHome\Watchdog.ps1"
Copy-Item -Path ".\Watchdog.ps1" -Destination $watchdogScript

$watchdogVbsWrapper = @"
CreateObject("Wscript.Shell").Run "Powershell.exe -NoProfile -WindowStyle Hidden -File $watchdogScript", 0, true   
"@
$watchdogVbsWrapperFile = "$watchdogHome\WatchdogWrapper.vbs"
Out-File -FilePath $watchdogVbsWrapperFile -InputObject $watchdogVbsWrapper -NoNewLine

$watchdogTaskAction = New-ScheduledTaskAction `
    -Execute "$watchdogVbsWrapperFile" `
    -WorkingDirectory $watchdogHome 

$watchdogTaskTriggerNow = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days (365 * 50))

$watchdogTaskTrigger = @()
$watchdogTaskTrigger += $watchdogTaskTriggerNow

$watchdogTaskSettings = New-ScheduledTaskSettingsSet `
    -Hidden `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances Queue

$watchdogTask = Register-ScheduledTask `
    -Action $watchdogTaskAction `
    -Trigger $watchdogTaskTrigger `
    -Settings $watchdogTaskSettings `
    -TaskName $watchdogTaskName `
    -Description "Docker FTW Watchdog. Starts the WSL dockerd if it stops running."

$watchdogTask | Set-ScheduledTask
