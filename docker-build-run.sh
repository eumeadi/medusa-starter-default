#!/bin/bash

# docker-build-run.sh
# Script to build and run the Medusa Docker container
# Can be run manually or via cron job in the following steps...
# 1) crontab -e		#to open vim session.
# 2) 0 1 * * Mon /home/ec2-user/medusa/docker-build-run.sh >> /home/ec2-user/docker-cron.log 2>&1
# 3) :wq 			#to close vim session.
# 4) crontab -l  	#to confirm
# To run manually...
# 1) cd /home/ec2-user/medusa
# 2) ./docker-build-run.sh


# Configuration
APP_NAME="medusa"
APP_PATH="/home/ec2-user/medusa"
LOG_FILE="$APP_PATH/docker-deploy.log"
PORT=8000
CONTAINER_NAME="medusa"
ENV_FILE="$APP_PATH/.env.docker"

# Function for logging
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Create log file if it doesn't exist
touch "$LOG_FILE"

# Start deployment
log "Starting deployment process for $APP_NAME"
log "----------------------------------------"

# Navigate to application directory
cd "$APP_PATH" || {
  log "ERROR: Could not navigate to $APP_PATH"
  exit 1
}

# Check if .env file exists, create if it doesn't
if [ ! -f "$ENV_FILE" ]; then
  log "Creating .env file as it doesn't exist..."
  cat > "$ENV_FILE" << EOF
# Environment Variables for Medusa
# Created by docker-build-run.sh on $(date '+%Y-%m-%d %H:%M:%S')

MEDUSA_ADMIN_ONBOARDING_TYPE=default
STORE_CORS=http://localhost:8000,https://docs.medusajs.com
ADMIN_CORS=http://localhost:5173,http://localhost:9000,https://docs.medusajs.com
AUTH_CORS=http://localhost:5173,http://localhost:9000,https://docs.medusajs.com

REDIS_URL=redis://localhost:6379 # On Docker containers, use IP returned by Docker command: docker network inspect <NETWORK> 

JWT_SECRET=supersecret # Replace supersecret by generating with:  openssl rand -base64 32
COOKIE_SECRET=supersecret # Replace supersecret by generating with:  openssl rand -base64 32

DB_NAME=example
DATABASE_URL=postgres://example:supersecret@localhost/$DB_NAME
#DATABASE_URL=postgres://mesera:supersecret@postgres:5432/$DB_NAME?ssl_mode=disable

STRIPE_API_KEY= # The secret key of the stripe payment.
PAYSTACK_SECRET_KEY= # The secret key of the paystack payment.
SANITY_API_TOKEN= # The API token of the Sanity project.
SANITY_PROJECT_ID= # The ID of the Sanity project.
SANITY_STUDIO_URL=http://localhost:8000/studio

# Application configuration
PORT=9000

# Add all other environment variables here
EOF

  log ".env file created successfully."
else
  log ".env file already exists, skipping creation."
fi

# Check if docker is running
if ! docker info > /dev/null 2>&1; then
  log "ERROR: Docker is not running. Starting Docker service..."
  sudo service docker start
  sleep 5
  
  # Check again
  if ! docker info > /dev/null 2>&1; then
    log "ERROR: Failed to start Docker service. Exiting."
    exit 1
  fi
  
  log "Docker service started successfully."
fi

# Stop and remove existing container if it exists
if docker ps -a | grep -q "$CONTAINER_NAME"; then
  log "Stopping and removing existing container..."
  docker stop "$CONTAINER_NAME" > /dev/null 2>&1
  docker rm "$CONTAINER_NAME" > /dev/null 2>&1
  log "Existing container removed."
fi

# Build the Docker image
log "Building Docker image..."
if docker-compose "build"; then
  log "Docker image built successfully."
else
  log "ERROR: Failed to build Docker image. Exiting."
  exit 1
fi

# Start the container
log "Starting Docker container..."
if docker-compose up -d; then
  log "Docker container started successfully."
else
  log "ERROR: Failed to start Docker container. Exiting."
  exit 1
fi

# Wait for the application to start
log "Waiting for application to start..."
for i in {1..30}; do
  if curl -s "http://localhost:$PORT" > /dev/null; then
    log "Application is running on port $PORT."
    break
  fi
  
  if [ $i -eq 30 ]; then
    log "ERROR: Application failed to start within the timeout period."
    exit 1
  fi
  
  log "Still waiting... ($i/30)"
  sleep 2
done

# Check container status
CONTAINER_STATUS=$(docker inspect --format='{{.State.Status}}' "$CONTAINER_NAME" 2>/dev/null)
if [ "$CONTAINER_STATUS" = "running" ]; then
  log "Container is running properly."
else
  log "ERROR: Container is not running. Status: $CONTAINER_STATUS"
  log "Container logs:"
  docker logs "$CONTAINER_NAME" | tail -n 50 | tee -a "$LOG_FILE"
  exit 1
fi

# Print container information
log "Container information:"
docker ps | grep "$CONTAINER_NAME" | tee -a "$LOG_FILE"

# Check disk space
log "Checking disk space..."
df -h | grep -E '(Filesystem|/$)' | tee -a "$LOG_FILE"

# Clean up unused Docker resources
log "Cleaning up unused Docker resources..."
docker system prune -f > /dev/null 2>&1
log "Cleanup completed."

# Deployment completed
log "----------------------------------------"
log "Deployment completed successfully!"
log "Application is running at: http://localhost:$PORT"
log "----------------------------------------"

exit 0

