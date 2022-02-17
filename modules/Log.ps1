. .\modules\Globals.ps1

function Log {
    param([string] $Message, [switch] $CreateLogFile)
    $Append = !$CreateLogFile
    Out-File -FilePath $logFile -InputObject $Message -Append:$Append
    Write-Host $Message
}