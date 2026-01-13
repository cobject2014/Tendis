#!/bin/bash
set -e

IMAGE="tendis:2.8.3-rocksdb-v8.5.3-arm64"
CONF_FILE="tendisplus.conf"
DATA_DIR="tendis_data"

# Extract default configuration if it doesn't exist locally
if [ ! -f "$CONF_FILE" ]; then
    echo "Extracting default configuration from image..."
    TEMP_ID=$(docker create "$IMAGE")
    docker cp "$TEMP_ID:/app/tendisplus.conf" "$CONF_FILE"
    docker rm -v "$TEMP_ID" >/dev/null

    echo "Updating configuration for Docker usage..."
    # Update bind address to 0.0.0.0 to allow access from host
    # Update daemon to no because Docker container should run in foreground
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/^bind.*/bind 0.0.0.0/' "$CONF_FILE"
        sed -i '' 's/^daemon yes/daemon no/' "$CONF_FILE"
    else
        sed -i 's/^bind.*/bind 0.0.0.0/' "$CONF_FILE"
        sed -i 's/^daemon yes/daemon no/' "$CONF_FILE"
    fi
fi

# Create data directory on host
mkdir -p "$DATA_DIR"

# Run the container
echo "Starting Tendis container..."
# -p 51002:51002 : Map Tendis default port
# -v .../tendisplus.conf : Mount the modified config
# -v .../tendis_data:/app/home : Mount data directory. default config uses ./home/db, ./home/log etc.
docker run -d \
    --name tendis-server \
    -p 51002:51002 \
    -v "$(pwd)/$CONF_FILE:/app/tendisplus.conf" \
    -v "$(pwd)/$DATA_DIR:/app/home" \
    "$IMAGE"

echo "Container started."
echo "You can check logs with:   docker logs -f tendis-server"
echo "You can connect with:      redis-cli -p 51002"
