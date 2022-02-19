. .\modules\Globals.ps1
. .\modules\Log.ps1

Log -Message "Installing Portainer (a WebUI for managing docker containers) ..."

docker container stop portainer 
docker container rm portainer 
docker volume rm portainer_data

docker volume create portainer_data
docker run -d -p 9000:9000 --name portainer --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce:2.11.1

Log -Message "Portainer installed, you can access it through http://localhost:9000/ ..."