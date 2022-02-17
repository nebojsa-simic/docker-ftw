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




