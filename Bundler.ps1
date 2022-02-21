$source = [System.IO.File]::ReadAllText(".\Install.ps1")
$regexResults = $null
$replaced = @{}
do {
    $regexResults = $source | Select-String -Pattern '\. (?<file>\.(\\modules)*\\.+\.ps1)' -AllMatches
    foreach ($res in $regexResults.Matches) {
        $includeFile = $res.Groups[2]
        $included = [System.IO.File]::ReadAllText($includeFile)
        if ($replaced["$includeFile"]) {
            $included = ''
        }
        $source = $source.Replace($res.Value, $included)
        $replaced["$includeFile"] = $true      
    }
} while ($regexResults.Matches.Length -gt 1)
[System.IO.File]::WriteAllText("Installer-Bundle.ps1", $source)
