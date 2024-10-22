#!/bin/bash

echo "Starting installation..."
echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install steamcmd -y

# Create steam user with no password login
sudo useradd -m steam
sudo usermod -L steam  # Lock the password

# Create necessary directories and set permissions
sudo -u steam mkdir -p /home/steam/.local/share/Steam/steamapps/common/
sudo -u steam mkdir -p /home/steam/.steam/steamapps/common/

# Install satisfactory
STEAM_INSTALL_DIR="/home/steam/.local/share/Steam/steamapps/common/SatisfactoryDedicatedServer"
STEAM_INSTALL_SCRIPT="/usr/games/steamcmd +force_install_dir $STEAM_INSTALL_DIR +login anonymous +app_update 1690800 validate +quit"
sudo -u steam bash -c "$STEAM_INSTALL_SCRIPT"

# Create symbolic link for Steam's expected directory structure
sudo -u steam ln -s $STEAM_INSTALL_DIR /home/steam/.steam/steamapps/common/SatisfactoryDedicatedServer

# Create systemd service file with correct paths
sudo bash -c "cat << EOF > /etc/systemd/system/satisfactory.service
[Unit]
Description=Satisfactory dedicated server
Wants=network-online.target
After=syslog.target network.target nss-lookup.target network-online.target

[Service]
Environment=\"LD_LIBRARY_PATH=$STEAM_INSTALL_DIR/linux64\"
ExecStartPre=/usr/games/steamcmd +force_install_dir $STEAM_INSTALL_DIR +login anonymous +app_update 1690800 validate +quit
ExecStart=$STEAM_INSTALL_DIR/FactoryServer.sh
User=steam
Group=steam
StandardOutput=journal
Restart=always
RestartSec=15
KillSignal=SIGINT
WorkingDirectory=$STEAM_INSTALL_DIR

[Install]
WantedBy=multi-user.target
EOF"

sudo systemctl enable satisfactory
sudo systemctl start satisfactory

# Auto shutdown script
sudo bash -c 'cat << EOF > /home/ubuntu/auto-shutdown.sh
#!/bin/sh

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
EOF'

chmod +x /home/ubuntu/auto-shutdown.sh
chown ubuntu:ubuntu /home/ubuntu/auto-shutdown.sh

# Create auto-shutdown service
sudo bash -c 'cat << EOF > /etc/systemd/system/auto-shutdown.service
[Unit]
Description=Auto shutdown if no one is playing Satisfactory
After=satisfactory.service
Requires=satisfactory.service

[Service]
ExecStart=/home/ubuntu/auto-shutdown.sh
User=ubuntu
Group=ubuntu
StandardOutput=journal
Restart=always
RestartSec=60
KillSignal=SIGINT
WorkingDirectory=/home/ubuntu

[Install]
WantedBy=multi-user.target
EOF'

sudo systemctl daemon-reload
sudo systemctl enable auto-shutdown
sudo systemctl start auto-shutdown