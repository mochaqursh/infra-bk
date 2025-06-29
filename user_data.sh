#!/bin/bash

# Update system
apt-get update
apt-get upgrade -y

# Install required packages
apt-get install -y curl apt-transport-https ca-certificates gnupg lsb-release git

# Install Docker (official Docker installation)
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install Buildkite agent (following official Ubuntu guide)
# Add Buildkite's signed key
curl -fsSL https://keys.buildkite.com/buildkite-agent-archive-keyring.gpg | gpg --dearmor -o /usr/share/keyrings/buildkite-agent-archive-keyring.gpg

# Add the signed source to your list of repositories
echo "deb [signed-by=/usr/share/keyrings/buildkite-agent-archive-keyring.gpg] https://apt.buildkite.com/buildkite-agent stable main" | tee /etc/apt/sources.list.d/buildkite-agent.list

# Update package lists
apt-get update

# Install the agent
apt-get install -y buildkite-agent

# Configure Buildkite agent with token
sed -i "s/xxx/${buildkite_agent_token}/g" /etc/buildkite-agent/buildkite-agent.cfg

# Set agent name and other configurations
sed -i 's/# name="My-Agent-%hostname"/name="buildkite-agent-%hostname"/g' /etc/buildkite-agent/buildkite-agent.cfg

# Add buildkite-agent user to docker group so it can run Docker commands
usermod -aG docker buildkite-agent

# Enable and start Buildkite agent
systemctl enable buildkite-agent
systemctl start buildkite-agent

# Wait a moment for services to start
sleep 10

# Check status and log
systemctl status buildkite-agent >> /var/log/buildkite-setup.log
systemctl status docker >> /var/log/buildkite-setup.log

# Log installation completion
echo "Buildkite agent installation completed at $(date)" >> /var/log/buildkite-setup.log
echo "Agent should now be visible in Buildkite dashboard" >> /var/log/buildkite-setup.log