#!/bin/sh
# Create steam user with no password login
sudo useradd -m steam
sudo usermod -L steam  # Lock the password

echo "Starting installation..."
echo steam steam/question select "I AGREE" | sudo debconf-set-selections
echo steam steam/license note '' | sudo debconf-set-selections
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update

# Install required packages including AWS CLI v2
sudo apt install steamcmd curl unzip -y

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Get EC2 instance region from metadata service
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Configure AWS CLI for the steam user to use instance role credentials
sudo -u steam mkdir -p /home/steam/.aws
sudo bash -c 'cat << EOF > /home/steam/.aws/config
[default]
region = '"$REGION"'
EOF'

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
ExecStartPre=$STEAM_INSTALL_SCRIPT
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

# Create backup script
sudo bash -c "cat << 'EOF' > /home/steam/backup-saves.sh
#!/bin/bash

# Configuration
SAVE_DIR=\"/home/steam/.config/Epic/FactoryGame/Saved/SaveGames\"
S3_BUCKET=\"${S3_BUCKET}\"
BACKUP_PREFIX=\"${BACKUP_PREFIX}\"
RETENTION_DAYS=7

# Get instance ID for backup identification
INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)

# Create timestamp at runtime
TIMESTAMP=\$(date +%Y%m%d_%H%M%S)

# Create temporary backup directory
TEMP_DIR=\$(mktemp -d)
cp -r \"\$SAVE_DIR\"/* \"\$TEMP_DIR\" 2>/dev/null || true

# Compress saves
BACKUP_FILE=\"/tmp/satisfactory_backup_\$TIMESTAMP.tar.gz\"
tar -czf \"\$BACKUP_FILE\" -C \"\$TEMP_DIR\" . 2>/dev/null || true

# Upload to S3 using instance role credentials
aws s3 cp \"\$BACKUP_FILE\" \"s3://\${S3_BUCKET}/\${BACKUP_PREFIX}/\${INSTANCE_ID}/\${TIMESTAMP}/\" || {
    echo \"Failed to upload backup to S3\"
    exit 1
}

# Clean up local files
rm -rf \"\$TEMP_DIR\" \"\$BACKUP_FILE\"

# Delete old backups (older than RETENTION_DAYS)
aws s3 ls \"s3://\${S3_BUCKET}/\${BACKUP_PREFIX}/\${INSTANCE_ID}/\" | while read -r line;
do
    createDate=\$(echo \"\$line\" | awk '{print \$1}')
    createDate=\$(date -d \"\$createDate\" +%s)
    olderThan=\$(date -d \"\$RETENTION_DAYS days ago\" +%s)
    if [[ \$createDate -lt \$olderThan ]]
    then
        fileName=\$(echo \"\$line\" | awk '{print \$4}')
        if [ ! -z \"\$fileName\" ]
        then
            aws s3 rm \"s3://\${S3_BUCKET}/\${BACKUP_PREFIX}/\${INSTANCE_ID}/\${fileName}\"
        fi
    fi
done
EOF"

# Make backup script executable and set ownership
sudo chmod +x /home/steam/backup-saves.sh
sudo chown steam:steam /home/steam/backup-saves.sh

# Create systemd service for periodic backups
sudo bash -c 'cat << EOF > /etc/systemd/system/satisfactory-backup.service
[Unit]
Description=Satisfactory Save Game Backup Service
After=satisfactory.service
Requires=satisfactory.service

[Service]
Type=oneshot
ExecStart=/home/steam/backup-saves.sh
User=steam
Group=steam
EOF'

# Create systemd timer for periodic backups
sudo bash -c 'cat << EOF > /etc/systemd/system/satisfactory-backup.timer
[Unit]
Description=Run Satisfactory backup every hour

[Timer]
OnBootSec=15min
OnUnitActiveSec=1h

[Install]
WantedBy=timers.target
EOF'

# Create auto-shutdown script
sudo bash -c "cat << 'EOF' > /home/ubuntu/auto-shutdown.sh
#!/bin/bash
shutdownIdleMinutes=30
idleCheckFrequencySeconds=1

isIdle=0
while [ \$isIdle -le 0 ]; do
    isIdle=1
    iterations=\$((60 / \$idleCheckFrequencySeconds * \$shutdownIdleMinutes))
    while [ \$iterations -gt 0 ]; do
        sleep \$idleCheckFrequencySeconds
        connectionBytes=\$(ss -lu | grep 777 | awk -F \" \" '{s+=\$2} END {print s}')
        if [ ! -z \"\$connectionBytes\" ] && [ \$connectionBytes -gt 0 ]; then
            isIdle=0
        fi
        if [ \$isIdle -le 0 ] && [ \$((\$iterations % 21)) -eq 0 ]; then
            echo \"Activity detected, resetting shutdown timer to \$shutdownIdleMinutes minutes.\"
            break
        fi
        iterations=\$((\$iterations-1))
    done
done

echo \"No activity detected for \$shutdownIdleMinutes minutes, performing backup before shutdown.\"
sudo -u steam /home/steam/backup-saves.sh
echo \"Backup completed, shutting down.\"
sudo shutdown -h now
EOF"

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

# Make auto-shutdown script executable
sudo chmod +x /home/ubuntu/auto-shutdown.sh
sudo chown ubuntu:ubuntu /home/ubuntu/auto-shutdown.sh

# Enable and start all services
sudo systemctl daemon-reload
sudo systemctl enable satisfactory
sudo systemctl start satisfactory
sudo systemctl enable satisfactory-backup.timer
sudo systemctl start satisfactory-backup.timer
sudo systemctl enable satisfactory-backup.service
sudo systemctl start satisfactory-backup.service
sudo systemctl enable auto-shutdown
sudo systemctl start auto-shutdown