. .\modules\Globals.ps1
. .\modules\Log.ps1

Log -Message "Docker-FTW creating the `.docker-ftw` home folder in $HOME"

if (!(Test-Path -Path $dockerFtwHome)) {
    mkdir -p $dockerFtwHome | Out-Null
}

$dockerFtwVersionFile = "$dockerFtwHome\.version"
Out-File -FilePath $dockerFtwVersionFile -InputObject $dockerFtwVersion -NoNewLine

Log -Message "Docker-FTW done setting up the `.docker-ftw` home folder"