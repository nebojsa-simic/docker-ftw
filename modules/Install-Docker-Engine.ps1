. .\modules\Globals.ps1
. .\modules\Log.ps1

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
