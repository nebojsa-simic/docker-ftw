# https://stackoverflow.com/questions/7690994/running-a-command-as-administrator-using-powershell
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process PowerShell -Verb RunAs "-NoProfile -ExecutionPolicy Bypass -Command `"cd '$pwd'; & '$PSCommandPath';`"";
    Exit;
}

$dockerFtwVersion = "0.0.1"
$distro = "docker-ftw";
$dockerPort = 2376;
$alpineVersion = "3.15";
$alpineVersionFull = "3.15.0";
$dockerCliVersion = "20.10.9";
$arch = "x86_64";

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

Write-Host "Docker-FTW running preflight checks";

$dockerFtwAlreadyInstalled = (wsl -l).contains($distro)
if ($dockerFtwAlreadyInstalled) {
    Write-Host -NoNewLine "Docker-FTW already installed. Please uninstall and run the installer again ...";
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
    Exit;
}

$dockerPortAvailable = CheckPortIsAvailable -Port $dockerPort -Timeout 256
if (!$dockerPortAvailable) {
    Write-Host -NoNewLine "Something is already running on port $dockerPort. Please uninstall it and run the installer again ...";
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
    Exit;
}

Write-Host "Docker-FTW preflight checks succeded.";

Write-Host "Docker-FTW creating the `.docker-ftw` home folder in $HOME";

$dockerFtwHome = "$HOME\\.docker-ftw\\";
if (!(Test-Path -Path $dockerFtwHome)) {
    mkdir -p $dockerFtwHome;
}

$dockerFtwVersionFile = "$dockerFtwHome\\.version";
Out-File -FilePath $dockerFtwVersionFile -InputObject $dockerFtwVersion -NoNewLine

Write-Host "Docker-FTW installing docker daemon in the WSL2.";

$dockerFtwTmp = "$dockerFtwHome\\tmp"
mkdir -p $dockerFtwTmp;

$wslTar = "$dockerFtwTmp\\alpine-miniroot.tar.gz";
if (!(Test-Path -Path $wslTar -PathType Leaf)) {
    $source = "https://dl-cdn.alpinelinux.org/alpine/v$alpineVersion/releases/$arch/alpine-minirootfs-$alpineVersionFull-x86_64.tar.gz";
    Start-BitsTransfer -Source $source -Destination $wslTar;
}

$wslHome = "$dockerFtwHome\\wsl";
wsl --import $distro $wslHome $wslTar;

wsl --set-version $distro 2

wsl -d $distro apk update
wsl -d $distro apk add docker-engine
wsl -d $distro mkdir -p /etc/docker
wsl -d $distro ash -c 'echo \"{\\\"tls\\\": false,\\\"hosts\\\": [\\\"tcp://0.0.0.0:2376\\\", \\\"unix:///var/run/docker.sock\\\"]}\" > /etc/docker/daemon.json'
wsl -d $distro /usr/bin/nohup ash -c "/usr/bin/dockerd &"

Write-Host "Docker-FTW installing docker daemon succeeded.";

Write-Host "Docker-FTW setting the DOCKER_HOST environment variable.";

$dockerHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Machine');
if ($dockerHost) {
    Write-Host "Overwriting the DOCKER_HOST environment variable '$dockerHost' -> 'localhost:$dockerPort' ...";
}
[Environment]::SetEnvironmentVariable("DOCKER_HOST", "localhost:$dockerPort", 'Machine');

Write-Host "Docker-FTW setting DOCKER_HOST environment variable succeeded.";

if (!(Get-Command "docker.exe" -ErrorAction SilentlyContinue)) 
{ 
    Write-Host "Docker-FTW installing docker CLI.";
    
    $dockerCliZip = "$dockerFtwTmp\\docker-cli.zip";
    $dockerCliSource = "https://download.docker.com/win/static/stable/$arch/docker-$dockerCliVersion.zip";
    Start-BitsTransfer -Source $dockerCliSource -Destination $dockerCliZip;
    
    $dockerCliHome = "$dockerFtwHome\\docker-cli"
    Expand-Archive $dockerCliZip -DestinationPath $dockerCliHome

    Write-Host "Docker-FTW adding docker CLI to path.";

    $dockerCliPath = "$dockerCliHome\\docker"
    $Env:PATH = $Env:PATH + ";$dockerCliPath"
	$userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
	[Environment]::SetEnvironmentVariable("PATH", "$userPath;$dockerCliPath", "User")

    Write-Host "Docker-FTW docker CLI installed.";
}

Write-Host -NoNewLine "You can now use docker. Press 'any' key to finish the installation."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown");
Exit;