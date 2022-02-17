# https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell
function Request-Elevation {
    param([string] $RequestCommandPath)
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$requestCommandPath';`"";
        Exit
    }
}