. .\modules\Globals.ps1
. .\modules\Log.ps1
. .\modules\Wait-For-Keypress.ps1

Log -Message "Docker-FTW installation started: v$dockerFtwVersion" -CreateLogFile

$ErrorActionPreference = "SilentlyContinue"

. .\modules\Pre-Flight-Checks.ps1
. .\modules\Create-Home.ps1
. .\modules\Install-Docker-Engine.ps1
. .\modules\Add-Watchdog.ps1
. .\modules\Install-Docker-Cli.ps1

Log -Message "You can now use docker. Press 'any' key to finish the installation."
Wait-For-Keypress
Exit