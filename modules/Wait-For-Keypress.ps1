function Wait-For-Keypress {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}