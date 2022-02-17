# . .\modules\Request-Elevation.ps1

if ((wsl -l).contains("docker-ftw")) {
    wsl --unregister docker-ftw
}

$WatchdogTaskName = "docker-ftw-watchdog"
$WatchdogTask = Get-ScheduledTask | Where-Object { $_.TaskName -eq $WatchdogTaskName } | Select-Object -First 1
if ($null -ne $WatchdogTask) {
    # Request-Elevation -RequestCommandPath $PSCommandPath
    Unregister-ScheduledTask -TaskName "$WatchdogTaskName" -Confirm:$false
    # needs time to release it's grip on the folder
    Start-Sleep -Seconds 5
}

$dockerFtwHome = "$HOME\.docker-ftw"
if ((Test-Path -Path $dockerFtwHome)) {
    Remove-Item $dockerFtwHome -Recurse
}

$dockerCliHome = "$dockerFtwHome\docker-cli"
$dockerCliPath = "$dockerCliHome\docker"

$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
$changedUserPath = $userPath.Split(";") |
    ForEach-Object { $_.TrimEnd("\") } |
    Where-Object { $_ -ne $dockerCliPath }

$changedUserPath = $changedUserPath -Join ";"

if ($userPath -ne $changedUserPath) {
    [Environment]::SetEnvironmentVariable("PATH", "$changedUserPath", "User")
    $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $env:PATH += ";$changedUserPath"
}

[Environment]::SetEnvironmentVariable("DOCKER_HOST", $null, 'User')

Write-Host -NoNewLine "Docker-FTW uninstalled. Press 'any' key to exit ...";
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");