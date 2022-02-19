$dockerFtwVersion = "0.0.1"
$distro = "docker-ftw"
$dockerPort = 2376
$alpineVersion = "3.15"
$alpineVersionFull = "3.15.0"
$dockerCliVersion = "20.10.9"
$arch = "x86_64"
$logFile = "install.log"
$watchdogTaskName = "docker-ftw-watchdog"
$dockerFtwHome = "$HOME\.docker-ftw"


function Log {
    param([string] $Message, [switch] $CreateLogFile)
    $Append = !$CreateLogFile
    Out-File -FilePath $logFile -InputObject $Message -Append:$Append
    Write-Host $Message
}
function Wait-For-Keypress {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

Log -Message "Docker-FTW installation started: v$dockerFtwVersion" -CreateLogFile

$ErrorActionPreference = "SilentlyContinue"




Log -Message "Docker-FTW running preflight checks"

function CheckPortIsAvailable {
    param([string] $Address = "localhost", $Port = $dockerPort, $Timeout = 3000)

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

if (!(Test-Path -Path $dockerFtwHome)) {
    mkdir -p $dockerFtwHome | Out-Null
}

$dockerFtwVersionFile = "$dockerFtwHome\.version"
Out-File -FilePath $dockerFtwVersionFile -InputObject $dockerFtwVersion -NoNewLine

Log -Message "Docker-FTW done setting up the `.docker-ftw` home folder"



Log -Message "Docker-FTW installing docker-engine in the WSL2."

if ((wsl -l).contains($distro)) {
    wsl --unregister $distro
}

$dockerFtwTmp = "$dockerFtwHome\tmp"
New-Item -ItemType Directory -Force -Path $dockerFtwTmp | Out-Null

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

Log -Message "Docker-FTW installing docker-engine succeeded."

Log -Message "Docker-FTW setting the DOCKER_HOST environment variable."

$dockerHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'User')
if ($dockerHost) {
    Log -Message "Overwriting the DOCKER_HOST environment variable '$dockerHost' -> 'localhost:$dockerPort' ..."
}
[Environment]::SetEnvironmentVariable("DOCKER_HOST", "localhost:$dockerPort", 'User')

Log -Message "Docker-FTW setting DOCKER_HOST environment variable succeeded."



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




if (!(Get-Command "docker.exe" -ErrorAction SilentlyContinue)) { 
    Log -Message "Docker-FTW installing docker CLI v$dockerCliVersion."
    
    $dockerFtwTmp = "$dockerFtwHome\tmp"
    New-Item -ItemType Directory -Force -Path $dockerFtwTmp | Out-Null

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
} else {
    Log -Message "Docker-FTW docker CLI is already installed, I am choosing to not overwrite it."
}



Log -Message "Installing Portainer (a WebUI for managing docker containers) ..."

docker container stop portainer 
docker container rm portainer 
docker volume rm portainer_data

docker volume create portainer_data
docker run -d -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.11.1

Log -Message "Portainer installed, you can access it through http://localhost:9000/ ..."

Log -Message "You can now use docker. Press 'any' key to finish the installation."
Wait-For-Keypress
Exit