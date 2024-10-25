#!/bin/bash
S3_BUCKET="${s3_bucket}"
BACKUP_PREFIX="${backup_prefix}"

# Validate input parameters
if [ -z "$S3_BUCKET" ] || [ -z "$BACKUP_PREFIX" ]; then
    echo "Required template variables not set"
    exit 1
fi

echo "Starting installation..."
echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update
sudo apt install steamcmd curl unzip -y

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Install AWS CLI if not present
if ! command -v aws &> /dev/null; then
    sudo apt install awscli -y
fi

# Create steam user with no password login
sudo useradd -m steam
sudo usermod -L steam  # Lock the password

# Create necessary directories and set permissions
sudo -u steam mkdir -p /home/steam/.local/share/Steam/steamapps/common/
sudo -u steam mkdir -p /home/steam/.steam/steamapps/common/

# Install satisfactory
STEAM_INSTALL_DIR="/home/steam/.local/share/Steam/steamapps/common/SatisfactoryDedicatedServer"
STEAM_INSTALL_SCRIPT="/usr/games/steamcmd +force_install_dir $STEAM_INSTALL_DIR +login anonymous +app_update 1690800 validate +quit"

# Create save directory manually to avoid missing save files folder issue
sudo -u steam mkdir -p /home/steam/.config/Epic/FactoryGame/Saved/SaveGames/server
sudo -u steam bash -c "$STEAM_INSTALL_SCRIPT"

# Create symbolic link for Steam's expected directory structure
sudo -u steam ln -s $STEAM_INSTALL_DIR /home/steam/.steam/steamapps/common/SatisfactoryDedicatedServer

# Create backup script
# Create backup script
sudo bash -c "cat << 'EOF' > /home/steam/backup-saves.sh
#!/bin/bash

# Enable logging
exec 1> >(logger -s -t \$(basename \$0)) 2>&1

# Exit on error
set -e

echo 'Starting backup process...'
TOKEN=\$(curl -X PUT 'http://169.254.169.254/latest/api/token' -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600' 2>/dev/null)
if [ -z \"\$TOKEN\" ]; then
    echo 'Failed to retrieve IMDSv2 token'
    INSTANCE_ID='unknown-instance'
    REGION='us-east-1'  # Default region
else
    INSTANCE_ID=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" -s http://169.254.169.254/latest/meta-data/instance-id)
    REGION=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" -s http://169.254.169.254/latest/meta-data/placement/region)

    # Verify we got the values
    if [ -z \"\$INSTANCE_ID\" ]; then
        echo 'Failed to retrieve instance ID'
        INSTANCE_ID='unknown-instance'
    fi

    if [ -z \"\$REGION\" ]; then
        echo 'Failed to retrieve region'
        REGION='us-east-1'  # Default region
    fi
fi

# Get save file directory
SAVE_DIR=/home/steam/.config/Epic/FactoryGame/Saved/SaveGames/server

# Create timestamp
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

# Create backup directory
BACKUP_DIR=/tmp/satisfactory_backup_\$TIMESTAMP
mkdir -p \$BACKUP_DIR

# Copy save files
echo 'Copying save files to \$BACKUP_DIR'
cp -rv \$SAVE_DIR \$BACKUP_DIR

# Create tar archive
cd /tmp
echo 'Creating tar archive'
tar -czf satisfactory_backup_\$TIMESTAMP.tar.gz satisfactory_backup_\$TIMESTAMP

# Upload to S3 with instance metadata tags
echo 'Uploading to S3'
aws s3 cp satisfactory_backup_\$TIMESTAMP.tar.gz s3://${s3_bucket}/${backup_prefix}/\$INSTANCE_ID/\$TIMESTAMP/satisfactory_backup_\$TIMESTAMP.tar.gz \\
    --region \$REGION \\
    --debug

# Cleanup
echo 'Cleaning up temporary files'
rm -rf \$BACKUP_DIR
rm satisfactory_backup_\$TIMESTAMP.tar.gz

echo 'Backup completed successfully'
EOF"

chmod +x /home/steam/backup-saves.sh
chown steam:steam /home/steam/backup-saves.sh

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

# Auto shutdown script
sudo bash -c 'cat << '\''EOF'\'' > /home/ubuntu/auto-shutdown.sh
#!/bin/sh

shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ $isIdle -le 0 ]; do
    isIdle=1
    iterations=$((60 / $idleCheckFrequencySeconds * $shutdownIdleMinutes))
    while [ $iterations -gt 0 ]; do
        sleep $idleCheckFrequencySeconds
        connectionBytes=$(ss -lu | grep 777 | awk -F " " "{s+=\$2} END {print s}")
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
sudo systemctl enable satisfactory
sudo systemctl start satisfactory
sudo systemctl enable auto-shutdown
sudo systemctl start auto-shutdown

sudo bash -c "cat << EOF > /etc/systemd/system/satisfactory-backup.timer
[Unit]
Description=Run satisfactory-backup.service every 5 minutes

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF"

# Create pre-shutdown backup service
sudo bash -c "cat << EOF > /etc/systemd/system/satisfactory-backup.service
[Unit]
Description=Backup Satisfactory saves every 5 minutes
After=network-online.target

[Service]
Type=oneshot
ExecStart=/home/steam/backup-saves.sh
TimeoutStartSec=300
User=steam
Group=steam
EOF"

# Enable the backup service
sudo systemctl daemon-reload
sudo systemctl enable satisfactory-backup.timer
sudo systemctl start satisfactory-backup.timer
sudo systemctl enable satisfactory-backup.service
sudo systemctl start satisfactory-backup.service