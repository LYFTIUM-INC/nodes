#!/bin/bash
set -e

echo "🚀 Starting MEV Relay Aggregator..."

# Wait for Redis to be ready
echo "⏳ Waiting for Redis..."
while ! nc -z redis 6379; do
  sleep 1
done
echo "✅ Redis is ready"

# Create log directory
mkdir -p /app/logs

# Start the application
echo "🌟 Starting MEV Relay Aggregator service..."
python main.py