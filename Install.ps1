# https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    Exit
}

$dockerFtwVersion = "0.0.1"
$distro = "docker-ftw"
$dockerPort = 2376
$alpineVersion = "3.15"
$alpineVersionFull = "3.15.0"
$dockerCliVersion = "20.10.9"
$arch = "x86_64"
$installLogFile = "install.log"
$watchdogTaskName = "docker-ftw-watchdog"

function Log {
    param([string] $Message, [switch] $Append = $true)
    Out-File -FilePath $installLogFile -InputObject $Message -Append:$Append
    Write-Host $Message
}

Log -Message "Docker-FTW installation started: v$dockerFtwVersion" -Append:$false

$ErrorActionPreference = "SilentlyContinue"
 
function CheckPortIsAvailable {
    param([string] $Address = "localhost", $Port = 2376, $Timeout = 3000)

    $Task = [system.net.dns]::GetHostAddressesAsync($Address)
    [Threading.Tasks.Task]::WaitAll($Task)
    if ($Task.IsFaulted) {
        return $true
    }
    
    foreach ($Ip in $Task.Result) {
        $TcpClient = new-Object system.Net.Sockets.TcpClient -ArgumentList $Ip.AddressFamily
        $ConnectResult = $TcpClient.ConnectAsync($Ip, $Port).Wait($Timeout)
        if ($ConnectResult) {
            return $false
        }
    }
    return $true
} 

Log -Message "Docker-FTW running preflight checks"

$dockerFtwAlreadyInstalled = (wsl -l).contains($distro)
if ($dockerFtwAlreadyInstalled) {
    Log -Message "Docker-FTW already installed. Please uninstall and run the installer again ..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Exit
}

$dockerPortAvailable = CheckPortIsAvailable -Port $dockerPort -Timeout 256
if (!$dockerPortAvailable) {
    Log -Message "Something is already running on port $dockerPort. Please uninstall it and run the installer again ..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Exit
}

Log -Message "Docker-FTW preflight checks succeded."

Log -Message "Docker-FTW creating the `.docker-ftw` home folder in $HOME"

$dockerFtwHome = "$HOME\.docker-ftw"
if (!(Test-Path -Path $dockerFtwHome)) {
    mkdir -p $dockerFtwHome | Out-Null
}

$dockerFtwVersionFile = "$dockerFtwHome\.version"
Out-File -FilePath $dockerFtwVersionFile -InputObject $dockerFtwVersion -NoNewLine

Log -Message "Docker-FTW installing docker daemon in the WSL2."

$dockerFtwTmp = "$dockerFtwHome\tmp"
mkdir -p $dockerFtwTmp | Out-Null

Log -Message "Docker-FTW installing alpine $alpineVersion in the WSL2 $distro instance."

$wslTar = "$dockerFtwTmp\alpine-miniroot.tar.gz"
if (!(Test-Path -Path $wslTar -PathType Leaf)) {
    $source = "https://dl-cdn.alpinelinux.org/alpine/v$alpineVersion/releases/$arch/alpine-minirootfs-$alpineVersionFull-x86_64.tar.gz"
    Start-BitsTransfer -Source $source -Destination $wslTar
}

$wslHome = "$dockerFtwHome\wsl"
wsl --import $distro $wslHome $wslTar

wsl --set-version $distro 2

Log -Message "Docker-FTW installing docker-engine in the WSL2 $distro instance."

wsl -d $distro apk update
wsl -d $distro apk add docker-engine
wsl -d $distro mkdir -p /etc/docker
wsl -d $distro ash -c 'echo \"{\\\"tls\\\": false,\\\"hosts\\\": [\\\"tcp://0.0.0.0:2376\\\", \\\"unix:///var/run/docker.sock\\\"]}\" > /etc/docker/daemon.json'

Log -Message "Docker-FTW starting dockerd"

wsl -d $distro /usr/bin/nohup ash -c "/usr/bin/dockerd &"

Log -Message "Docker-FTW installing docker daemon succeeded."

Log -Message "Docker-FTW adding watchdog."

$watchdogHome = "$dockerFtwHome\watchdog"
mkdir -p $watchdogHome | Out-Null

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

$watchdogTaskTriggerNow = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1)
$watchdogTaskTriggerDaily = New-ScheduledTaskTrigger -Daily -At 12AM
$watchdogTaskTriggerAtLogon = New-ScheduledTaskTrigger -AtLogOn

$watchdogTaskTrigger = @()
$watchdogTaskTrigger += $watchdogTaskTriggerNow
$watchdogTaskTrigger += $watchdogTaskTriggerDaily
$watchdogTaskTrigger += $watchdogTaskTriggerAtLogon

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

$watchdogTaskTriggerDaily.Triggers.Repetition.Duration = "P1D"
$watchdogTaskTriggerDaily.Triggers.Repetition.Interval = "PT30M"

$watchdogTask | Set-ScheduledTask

Log -Message "Docker-FTW setting the DOCKER_HOST environment variable."

$dockerHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'User')
if ($dockerHost) {
    Log -Message "Overwriting the DOCKER_HOST environment variable '$dockerHost' -> 'localhost:$dockerPort' ..."
}
[Environment]::SetEnvironmentVariable("DOCKER_HOST", "localhost:$dockerPort", 'User')

Log -Message "Docker-FTW setting DOCKER_HOST environment variable succeeded."

if (!(Get-Command "docker.exe" -ErrorAction SilentlyContinue)) { 
    Log -Message "Docker-FTW installing docker CLI v$dockerCliVersion."
    
    $dockerCliZip = "$dockerFtwTmp\docker-cli.zip"
    $dockerCliSource = "https://download.docker.com/win/static/stable/$arch/docker-$dockerCliVersion.zip"
    Start-BitsTransfer -Source $dockerCliSource -Destination $dockerCliZip
    
    $dockerCliHome = "$dockerFtwHome\docker-cli"
    Expand-Archive $dockerCliZip -DestinationPath $dockerCliHome

    Log -Message "Docker-FTW adding docker CLI to path."

    $dockerCliPath = "$dockerCliHome\docker"
    $Env:PATH = $Env:PATH + ";$dockerCliPath"
	$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
	[Environment]::SetEnvironmentVariable("PATH", "$userPath;$dockerCliPath", "User")

    Log -Message "Docker-FTW docker CLI installed."
}

Log -Message "You can now use docker. Press 'any' key to finish the installation."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Exit