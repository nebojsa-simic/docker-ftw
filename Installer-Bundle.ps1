$dockerFtwVersion = "0.0.2"
$distro = "docker-ftw"
$dockerPort = 2376
$alpineVersion = "3.18"
$alpineVersionFull = "3.18.2"
$dockerCliVersion = "24.0.2"
$buildxCliPluginVersion = "0.11.0"
$arch = "x86_64"
$logFile = "install.log"
$watchdogTaskName = "docker-ftw-watchdog"
$dockerFtwHome = "$HOME\.docker-ftw"
$dockerHome = "$HOME\.docker"


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
wsl -d $distro apk add docker-engine docker-cli
wsl -d $distro mkdir -p /etc/docker
wsl -d $distro ash -c 'echo \"{\\\"experimental\\\": true,\\\"tls\\\": false,\\\"hosts\\\": [\\\"tcp://0.0.0.0:2376\\\", \\\"unix:///var/run/docker.sock\\\"]}\" > /etc/docker/daemon.json'

Log -Message "Docker-FTW starting dockerd"

wsl -d $distro /usr/bin/nohup ash -c "/usr/bin/dockerd &"
Sleep -Seconds 5

Log -Message "Docker-FTW installing binfmt for arm64 platform."
wsl -d $distro docker run --privileged --rm tonistiigi/binfmt --install arm64

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
$watchdogScriptContent = @'
$watchdogLogFile = 'watchdog.log'
$distro = 'docker-ftw'
$watchHost = 'localhost'
$watchPort = 2376
$connectionTimeout = 512
$receiveBuffer = new-object System.Byte[] 1

function Log {
    param([string] $Message, [switch] $CreateLogFile)
    Out-File -FilePath $watchdogLogFile -InputObject $Message -Append:!$CreateLogFile
    Write-Host $Message
}

$powershellProcessesRunning = (Get-WmiObject win32_process | Where {$_.name -eq "powershell.exe"})

foreach ($powershellProcess in $powershellProcessesRunning) {
    $isSameProcessCommandLine = $powershellProcess.CommandLine.EndsWith($MyInvocation.MyCommand.Definition)
    $isSamePid = $PID -Eq $powershellProcess.ProcessId
    if (!$isSamePid -And $isSameProcessCommandLine) {
        Log -Message "Watchdog already running, exiting ..."
        Exit
    }
}

Log -Message 'Watchdog started' -CreateLogFile

$dockerFtwInstalled = (wsl -l).contains($distro)
if (!$dockerFtwInstalled) {
    Log -Message "Docker-FTW not installed."
    Exit
}

while ($true) {

    $Task = [system.net.dns]::GetHostAddressesAsync($watchHost)
    [Threading.Tasks.Task]::WaitAll($Task)
    if ($Task.IsFaulted) {
        Log -Message 'Watchdog can not connect to $watchHost'
        Exit
    }

    foreach ($Ip in $Task.Result) {
        $TcpClient = new-Object system.Net.Sockets.TcpClient -ArgumentList $Ip.AddressFamily
        $TcpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]"Socket", [System.Net.Sockets.SocketOptionName]"KeepAlive", $true);
        # $TcpClient.Client.SetSocketOption([System.Net.Sockets.SocketOptionLevel]"Tcp", [System.Net.Sockets.SocketOptionName]"TcpKeepAliveTime", 30000);

        Log -Message "Watchdog connecting to $Ip on port $watchPort"
        $ConnectResult = $TcpClient.ConnectAsync($Ip, $watchPort).Wait($connectionTimeout)
        if ($ConnectResult) {
            Log -Message "Watchdog connected to $Ip on port $watchPort"
            while ($true) {
                if (!$TcpClient.Connected) {
                    break;
                }
                # If the client has connected, this will block until the connection is lost
                if ($TcpClient.Client.Receive($receiveBuffer, [System.Net.Sockets.SocketFlags]"Peek") -Eq 0) {
                    break;
                }
                # This will never be called
                Log -Message "Watchdog still connected to $Ip on port $watchPort"
                Start-Sleep -Seconds 30
            }
            Log -Message "Watchdog disconnected from $Ip on port $watchPort."
        } else {
            Log -Message "Watchdog couldn't connect to $Ip on port $watchPort"
        }
    }

    Log -Message "Watchdog starting dockerd"
    $wslOutput = (wsl -d $distro /usr/bin/nohup ash -c "/usr/bin/dockerd &")
    if ($wslOutput -And $wslOutput.contains("There is no distribution with the supplied name.")) {
        Log -Message "Watchdog exiting, docker-ftw uninstalled"
        Exit
    }
    Start-Sleep -Seconds 5
}





'@
Out-File -FilePath $watchdogScript -InputObject $watchdogScriptContent

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

    Log -Message "Docker-FTW setting DOCKER_CLI_EXPERIMENTAL environment variable to `enabled`."

    [Environment]::SetEnvironmentVariable("DOCKER_CLI_EXPERIMENTAL", "enabled", 'User')

    Log -Message "Downloading buildx plugin."

    $dockerConfigFolder = "$env:userprofile/.docker"
    if(!(Test-Path $dockerConfigFolder)){ $null = new-item -Type Directory -Path $dockerConfigFolder}
    $dockerCliPluginFolder = "$dockerConfigFolder/cli-plugins"
    if(!(Test-Path $dockerCliPluginFolder)){ $null = new-item -Type Directory -Path $dockerCliPluginFolder}

    $dockerBuildXExe = "$dockerCliPluginFolder\docker-buildx.exe"
    $dockerBuildXSource = "https://github.com/docker/buildx/releases/download/v$buildxCliPluginVersion/buildx-v$buildxCliPluginVersion.windows-amd64.exe"
    Start-BitsTransfer -Source $dockerBuildXSource -Destination $dockerBuildXExe

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