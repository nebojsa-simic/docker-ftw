. .\modules\Globals.ps1
. .\modules\Log.ps1

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