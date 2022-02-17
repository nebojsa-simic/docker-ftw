. .\modules\Globals.ps1
. .\modules\Log.ps1

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