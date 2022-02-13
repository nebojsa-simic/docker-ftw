# https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    Exit;
}

if ((wsl -l).contains("docker-ftw")) {
    wsl --unregister docker-ftw;
}

$dockerFtwHome = "$HOME\\.docker-ftw\\"
if ((Test-Path -Path $dockerFtwHome)) {
    Remove-Item $dockerFtwHome -Recurse;
}

$dockerCliHome = "$dockerFtwHome\\docker-cli";
$dockerCliPath = "$dockerCliHome\\docker";

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

Write-Host -NoNewLine "Docker-FTW uninstalled. Press 'any' key to exit ...";
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");