# #!/bin/sh

# # Note: Arguments to this script 
# #  1: string - S3 bucket for your backup save files (required)
# S3_SAVE_BUCKET=$1

echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
sudo add-apt-repository multiverse -y; sudo dpkg --add-architecture i386; sudo apt update
sudo apt install steamcmd -y
# install aws cli: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
# sudo snap install aws-cli --classic

# install satisfactory: https://satisfactory.fandom.com/wiki/Dedicated_servers
STEAM_INSTALL_SCRIPT="steamcmd +force_install_dir ~/SatisfactoryDedicatedServer +login anonymous +app_update 1690800 -beta public validate +quit"
# note, we are switching users because steam doesn't recommend running steamcmd as root
eval "$STEAM_INSTALL_SCRIPT"

# enable as server so it stays up and start: https://satisfactory.fandom.com/wiki/Dedicated_servers/Running_as_a_Service
# sudo systemctl status satisfactory
sudo bash -c 'cat << EOF > /etc/systemd/system/satisfactory.service
[Unit]
Description=Satisfactory dedicated server
Wants=network-online.target
After=syslog.target network.target nss-lookup.target network-online.target
[Service]
Environment="LD_LIBRARY_PATH=./linux64"
ExecStartPre=$STEAM_INSTALL_SCRIPT
ExecStart=/home/ubuntu/SatisfactoryDedicatedServer/FactoryServer.sh
User=ubuntu
Group=ubuntu
StandardOutput=journal
Restart=on-failure
KillSignal=SIGINT
WorkingDirectory=/home/ubuntu/SatisfactoryDedicatedServer
[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl enable satisfactory
sudo systemctl start satisfactory

# # enable auto shutdown: https://github.com/feydan/satisfactory-tools/tree/main/shutdown
sudo bash -c 'cat << EOF > /home/ubuntu/auto-shutdown.sh
!/bin/sh

shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ $isIdle -le 0 ]; do
    isIdle=1
    iterations=$((60 / $idleCheckFrequencySeconds * $shutdownIdleMinutes))
    while [ $iterations -gt 0 ]; do
        sleep $idleCheckFrequencySeconds
        connectionBytes=$(ss -lu | grep 777 | awk -F ' ' '{s+=$2} END {print s}')
        if [ ! -z $connectionBytes ] && [ $connectionBytes -gt 0 ]; then
            isIdle=0
        fi
        if [ $isIdle -le 0 ] && [ $(($iterations % 21)) -eq 0 ]; then
           echo "Activity detected, resetting shutdown timer to $shutdownIdleMinutes minutes."
           break
        fi
        iterations=$(($iterations-1))
    done
done

echo "No activity detected for $shutdownIdleMinutes minutes, shutting down."
sudo shutdown -h now
EOF
chmod +x /home/ubuntu/auto-shutdown.sh
chown ubuntu:ubuntu /home/ubuntu/auto-shutdown.sh

cat << 'EOF' > /etc/systemd/system/auto-shutdown.service
[Unit]
Description=Auto shutdown if no one is playing Satisfactory
After=syslog.target network.target nss-lookup.target network-online.target

[Service]
Environment="LD_LIBRARY_PATH=./linux64"
ExecStart=/home/ubuntu/auto-shutdown.sh
User=ubuntu
Group=ubuntu
StandardOutput=journal
Restart=on-failure
KillSignal=SIGINT
WorkingDirectory=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF'
sudo systemctl enable auto-shutdown
sudo systemctl start auto-shutdown

# # automated backups to s3 every 5 minutes
# # su - ubuntu -c "crontab -l -e ubuntu | { cat; echo \"*/5 * * * * /usr/local/bin/aws s3 sync /home/ubuntu/.config/Epic/FactoryGame/Saved/SaveGames/server s3://$S3_SAVE_BUCKET\"; } | crontab -"