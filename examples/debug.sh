#!/bin/bash

# ToDo: find a cleaner way to monitor both processes

set -e

export REGISTRAR_TOKEN="123456"
export PEACEFOUNDER_SERVICE="http://localhost:4584"

# Function to cleanup background processes
cleanup() {
    echo "Shutting down services..."
    if [[ -n "$PEACEFOUNDER_PID" ]]; then
        kill $PEACEFOUNDER_PID 2>/dev/null || true
    fi
    if [[ -n "$REGISTRAR_PID" ]]; then
        kill $REGISTRAR_PID 2>/dev/null || true
    fi
    wait 2>/dev/null || true
    echo "Services stopped."
    exit 0
}

# Set trap to cleanup on script exit
trap cleanup SIGINT SIGTERM EXIT

echo "Starting debug services..."

# Start PeaceFounder service in background
echo "Starting PeaceFounder service..."
julia --project=. main.jl --load=examples/integration/setup.jl

#&
#PEACEFOUNDER_PID=$!

# Wait a moment for PeaceFounder to start
#sleep 2

# Start Registrar integration in background  
echo "Starting Registrar integration..."
julia --project=examples/integration main.jl &
REGISTRAR_PID=$!

echo "Debug services started:"
echo "  PeaceFounder service: http://localhost:4584 (PID: $PEACEFOUNDER_PID)"
echo "  Registrar integration: http://localhost:3456 (PID: $REGISTRAR_PID)"
echo ""
echo "Press Ctrl+C to stop both services"

# Wait for both processes
wait
