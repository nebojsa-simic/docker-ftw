# docker-ftw (Docker For The Windows)

Setup Docker for Windows withut Docker Desktop.

With PowerShell, you must ensure Get-ExecutionPolicy is not Restricted. 
I suggest using `Bypass` to bypass the policy and get the things installed.

- Open a PowerShell console (Win + x, i)
- Run `Get-ExecutionPolicy`. If it returns `Restricted` or `RemoteSigned`, then you have to run `Set-ExecutionPolicy Bypass -Scope Process`
- Next run `./Install.ps1`
- Close the PowerShell console
- Open a new PowerShell console (Win + x, i)
- Run `docker run -it hello-world` to confirm it works

To uninstall everything, just run `./Uninstall.ps1`
