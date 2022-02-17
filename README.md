# docker-ftw (Docker For The Windows)

Setup Docker for Windows withut using Docker Desktop.

## Installation 

With PowerShell, you must ensure that execution policy is not Restricted. 
I suggest using `Bypass` to bypass the policy and get the things installed.

- Open a PowerShell console (Win + x, i)
- Run `Set-ExecutionPolicy Bypass -Scope Process`
- Run `./Install.ps1`
- Run `docker run -it hello-world` to confirm it works

## Update/Upgrade

Currently the update/upgrade path is not implemented. To update simply uninstall and then install docker-ftw again. This will delete all your docker containers, volumes, images etc.

## Uninstallation 

To uninstall everything, just run `./Uninstall.ps1`

## Troubleshooting

### No connection to the docker daemon

If you get the following message:
```
error during connect: Get "http://localhost:2376/v1.24/containers/json": dial tcp [::1]:2376: connectex: No connection could be made because the target machine actively refused it.
```

This means two things:
- the docker daemon in the WSL2 is not running and 
- there is something wrong with the docker-ftw watchdog that was supposed to restart the docker daemon when it dies.

There are a couple of things you can do:
- Wait for a minute or two and try again (seriously, this works most of the time)
- Run `wsl -d docker-ftw /usr/bin/nohup ash -c "/usr/bin/dockerd &"` - this will start docker daemon and fix your problem immediately, but the watchdog will still be dead and the problem might come-up again
- Open "Task  Scheduler" App, open "Task Scheduler Library", find the task "docker-ftw-watchdog" and run it - this will start the watchdog and it will in turn start the docker-daemon
- Re-install docker-ftw which will fix everything, but also delete all your docker containers, volumes, images etc.
