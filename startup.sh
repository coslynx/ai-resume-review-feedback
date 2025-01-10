Here is the production-ready `startup.sh` script for the AI-powered resume review MVP:

#!/bin/bash

set -euo pipefail

# Load environment variables
if [ -f .env ]; then
  source .env
fi

# Validate required environment variables
if [ -z "${REACT_APP_OPENAI_API_KEY}" ] || [ -z "${REACT_APP_STRIPE_PUBLIC_KEY}" ]; then
  echo "Error: Missing required environment variables" >&2
  exit 1
fi

# Set default values for optional variables
REACT_APP_API_BASE_URL="${REACT_APP_API_BASE_URL:-https://api.example.com}"
REACT_APP_GA_TRACKING_ID="${REACT_APP_GA_TRACKING_ID:-}"

# Directories and files
PROJECT_ROOT=$(pwd)
LOG_FILE="${PROJECT_ROOT}/logs/startup.log"
PID_FILE="${PROJECT_ROOT}/pids/startup.pid"

# Service timeouts and health check intervals
DB_TIMEOUT=60
BACKEND_TIMEOUT=120
FRONTEND_TIMEOUT=90
DB_HEALTH_CHECK_INTERVAL=5
BACKEND_HEALTH_CHECK_INTERVAL=10
FRONTEND_HEALTH_CHECK_INTERVAL=15

# Utility functions
log_info() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_error() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
}

cleanup() {
  log_info "Cleaning up processes and files..."
  if [ -f "$PID_FILE" ]; then
    kill $(cat "$PID_FILE") 2>/dev/null || true
    rm -f "$PID_FILE"
  fi
  log_info "Shutdown complete."
  exit 0
}

check_dependencies() {
  log_info "Verifying required dependencies..."
  command -v node >/dev/null 2>&1 || { log_error "Node.js is required but not installed. Aborting."; exit 1; }
  command -v npm >/dev/null 2>&1 || { log_error "NPM is required but not installed. Aborting."; exit 1; }
  command -v pg_ctl >/dev/null 2>&1 || { log_error "PostgreSQL is required but not installed. Aborting."; exit 1; }
  log_info "All dependencies verified."
}

check_port() {
  local port=$1
  if lsof -Pi :"$port" -sTCP:LISTEN -t >/dev/null; then
    log_error "Port $port is already in use. Aborting."
    return 1
  fi
  return 0
}

wait_for_service() {
  local service=$1
  local timeout=$2
  local health_check=$3
  local start_time=$(date +%s)
  local elapsed=0

  while [ $elapsed -lt $timeout ]; do
    if $health_check; then
      log_info "$service is ready."
      return 0
    fi
    sleep 1
    elapsed=$(($(date +%s) - start_time))
  done

  log_error "$service failed to start within $timeout seconds."
  return 1
}

verify_service() {
  local port=$1
  nc -z -w 5 localhost "$port"
}

start_database() {
  log_info "Starting PostgreSQL database..."
  pg_ctl start -l "$LOG_FILE" -w -t "$DB_TIMEOUT"
  if check_port 5432; then
    log_info "PostgreSQL database started successfully."
    return 0
  else
    log_error "Failed to start PostgreSQL database."
    return 1
  fi
}

start_backend() {
  log_info "Starting backend server..."
  npm start --prefix backend >> "$LOG_FILE" 2>&1 &
  local backend_pid=$!
  echo $backend_pid >> "$PID_FILE"
  if wait_for_service "Backend server" "$BACKEND_TIMEOUT" "verify_service 3000"; then
    log_info "Backend server started successfully."
    return 0
  else
    log_error "Failed to start backend server."
    return 1
  fi
}

start_frontend() {
  log_info "Starting frontend service..."
  npm start --prefix frontend >> "$LOG_FILE" 2>&1 &
  local frontend_pid=$!
  echo $frontend_pid >> "$PID_FILE"
  if wait_for_service "Frontend service" "$FRONTEND_TIMEOUT" "verify_service 8080"; then
    log_info "Frontend service started successfully."
    return 0
  else
    log_error "Failed to start frontend service."
    return 1
  fi
}

store_pid() {
  echo "$$" > "$PID_FILE"
}

trap cleanup EXIT ERR

check_dependencies
start_database
start_backend
start_frontend
store_pid

log_info "AI Resume Review MVP started successfully."
log_info "Backend server: http://localhost:3000"
log_info "Frontend service: http://localhost:8080"