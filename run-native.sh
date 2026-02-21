#!/bin/bash
set -e

# ============================================================
# DocGemma Native Runner
# Works on: RunPod, Vast.ai, Lambda Cloud, Paperspace,
#           AWS/GCP/Azure GPU VMs, bare metal, WSL2
# Usage: HF_TOKEN=hf_xxx bash run-native.sh
# ============================================================

# --- Configuration (override via env vars) ---
HF_TOKEN="${HF_TOKEN:-}"
DOCGEMMA_MODEL="${DOCGEMMA_MODEL:-google/medgemma-27b-it}"
VLLM_MAX_MODEL_LEN="${VLLM_MAX_MODEL_LEN:-8192}"
VLLM_GPU_UTIL="${VLLM_GPU_UTIL:-0.90}"
VLLM_PORT="${VLLM_PORT:-8000}"
APP_PORT="${APP_PORT:-8080}"
WORKDIR="${WORKDIR:-/workspace/docgemma}"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[ok]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[x]${NC} $1"; exit 1; }
step() { echo -e "\n${CYAN}=== $1 ===${NC}"; }

# --- Detect package manager ---
install_pkg() {
    if command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y -qq "$@" > /dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "$@" > /dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y -q "$@" > /dev/null 2>&1
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "$@" > /dev/null 2>&1
    else
        warn "Unknown package manager. Install manually: $*"
        return 1
    fi
}

install_node() {
    if command -v node &>/dev/null; then
        NODE_MAJOR=$(node --version | grep -oP '(?<=v)\d+')
        if [ "$NODE_MAJOR" -ge 18 ]; then
            log "Node.js $(node --version) already installed"
            return 0
        fi
    fi

    if command -v apt-get &>/dev/null; then
        curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
        apt-get install -y -qq nodejs > /dev/null 2>&1
    elif command -v dnf &>/dev/null || command -v yum &>/dev/null; then
        curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
        install_pkg nodejs
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        export NVM_DIR="$HOME/.nvm"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        nvm install 20
    fi

    log "Node.js $(node --version) installed"
}

install_uv() {
    if command -v uv &>/dev/null; then
        log "UV $(uv --version) already installed"
        return 0
    fi

    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="$HOME/.local/bin:$PATH"
    log "UV $(uv --version) installed"
}

# --- Detect environment ---
detect_environment() {
    if [ -n "$RUNPOD_POD_ID" ]; then
        echo "runpod"
    elif [ -n "$PAPERSPACE_FQDN" ]; then
        echo "paperspace"
    elif [ -n "$VAST_CONTAINERLABEL" ] || [ -n "$VAST_TCP_PORT_22" ]; then
        echo "vastai"
    elif [ -n "$LAMBDA_INSTANCE_ID" ] || grep -q "lambdalabs" /etc/hosts 2>/dev/null; then
        echo "lambda"
    elif curl -s -m 1 http://169.254.169.254/latest/meta-data/instance-id &>/dev/null; then
        echo "aws"
    elif curl -s -m 1 -H "Metadata-Flavor: Google" http://169.254.169.254/computeMetadata/v1/instance/id &>/dev/null; then
        echo "gcp"
    elif curl -s -m 1 -H "Metadata: true" "http://169.254.169.254/metadata/instance?api-version=2021-02-01" &>/dev/null; then
        echo "azure"
    else
        echo "generic"
    fi
}

get_access_url() {
    local env="$1"
    local port="$2"
    local public_ip

    case "$env" in
        runpod)
            echo "https://${RUNPOD_POD_ID}-${port}.proxy.runpod.net"
            ;;
        paperspace)
            echo "https://${PAPERSPACE_FQDN}:${port}"
            ;;
        *)
            public_ip=$(curl -s ifconfig.me 2>/dev/null || echo "localhost")
            echo "http://${public_ip}:${port}"
            ;;
    esac
}

# ============================================================
# MAIN
# ============================================================

echo -e "${CYAN}"
echo "  DocGemma Native Runner"
echo "  ======================"
echo -e "${NC}"

# --- Preflight checks ---
step "Preflight Checks"

ENVIRONMENT=$(detect_environment)
log "Environment: $ENVIRONMENT"

if [ -z "$HF_TOKEN" ]; then
    read -rp "Enter your HuggingFace token: " HF_TOKEN
    [ -z "$HF_TOKEN" ] && err "HF_TOKEN is required. Get one at https://huggingface.co/settings/tokens"
fi

if ! command -v nvidia-smi &>/dev/null; then
    err "nvidia-smi not found. This script requires an NVIDIA GPU."
fi

GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader | head -1)
GPU_MEM=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -1)
GPU_COUNT=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
log "GPU: ${GPU_COUNT}x ${GPU_NAME} (${GPU_MEM}MB VRAM each)"

if [ "$GPU_MEM" -lt 20000 ]; then
    warn "Less than 20GB VRAM. Switching to medgemma-1.5-4b-it"
    DOCGEMMA_MODEL="google/medgemma-1.5-4b-it"
elif [ "$GPU_MEM" -lt 40000 ]; then
    warn "Less than 40GB VRAM. Switching to medgemma-1.5-4b-it (27B needs ~48GB)"
    DOCGEMMA_MODEL="google/medgemma-1.5-4b-it"
fi

log "Model: $DOCGEMMA_MODEL"
log "Context: $VLLM_MAX_MODEL_LEN tokens"
log "GPU util: $VLLM_GPU_UTIL"

# --- Check Python ---
if ! command -v python3 &>/dev/null && ! command -v python &>/dev/null; then
    err "Python 3.12+ not found."
fi
PYTHON=$(command -v python3 || command -v python)
PY_VER=$($PYTHON --version)
log "Python: $PY_VER"

# --- Install system dependencies ---
step "Installing System Dependencies"

install_pkg curl git
install_node
install_uv
log "System dependencies ready"

# --- Install vLLM ---
step "Installing vLLM"

pip install --upgrade pip --break-system-packages -q 2>/dev/null || pip install --upgrade pip -q
pip install vllm huggingface_hub --break-system-packages -q 2>/dev/null || pip install vllm huggingface_hub -q
log "vLLM installed"

# --- HuggingFace login ---
step "HuggingFace Authentication"

huggingface-cli login --token "$HF_TOKEN" 2>/dev/null
log "Authenticated with HuggingFace"

# --- Create workspace ---
mkdir -p "$WORKDIR"

# --- Clone repos ---
step "Cloning Repositories"

if [ -d "$WORKDIR/docgemma-connect" ]; then
    warn "docgemma-connect exists, pulling latest..."
    cd "$WORKDIR/docgemma-connect" && git pull --ff-only && cd "$WORKDIR"
else
    git clone --depth 1 https://github.com/galinilin/docgemma-connect.git "$WORKDIR/docgemma-connect"
fi

if [ -d "$WORKDIR/docgemma-frontend" ]; then
    warn "docgemma-frontend exists, pulling latest..."
    cd "$WORKDIR/docgemma-frontend" && git pull --ff-only && cd "$WORKDIR"
else
    git clone --depth 1 https://github.com/galinilin/docgemma-frontend.git "$WORKDIR/docgemma-frontend"
fi

log "Repos ready"

# --- Install backend dependencies ---
step "Setting Up Backend"

cd "$WORKDIR/docgemma-connect"
uv sync --frozen --no-dev
log "Backend dependencies installed"

# --- Build frontend and copy into backend static/ ---
step "Building Frontend"

cd "$WORKDIR/docgemma-frontend"
npm install --silent 2>/dev/null
VITE_API_URL=/api npm run build

mkdir -p "$WORKDIR/docgemma-connect/static"
cp -r "$WORKDIR/docgemma-frontend/dist/"* "$WORKDIR/docgemma-connect/static/"
log "Frontend built and copied to backend static/"

# --- PID management for cleanup ---
PIDDIR="/tmp/docgemma-pids"
mkdir -p "$PIDDIR"

cleanup() {
    echo -e "\n${YELLOW}Shutting down DocGemma...${NC}"
    for pidfile in "$PIDDIR"/*.pid; do
        if [ -f "$pidfile" ]; then
            PID=$(cat "$pidfile")
            kill "$PID" 2>/dev/null && log "Stopped PID $PID ($(basename "$pidfile" .pid))"
        fi
    done
    rm -rf "$PIDDIR"
    log "All services stopped"
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# --- Start vLLM ---
step "Starting vLLM"
echo -e "${YELLOW}First run downloads model weights (~54GB for MedGemma 27B, ~8GB for MedGemma 1.5 4B). This may take a while.${NC}"

VLLM_ARGS=(
    "$DOCGEMMA_MODEL"
    --max-model-len "$VLLM_MAX_MODEL_LEN"
    --gpu-memory-utilization "$VLLM_GPU_UTIL"
    --host 0.0.0.0
    --port "$VLLM_PORT"
)

# Multi-GPU: add tensor parallelism
if [ "$GPU_COUNT" -gt 1 ]; then
    VLLM_ARGS+=(--tensor-parallel-size "$GPU_COUNT")
    log "Multi-GPU: tensor parallelism across $GPU_COUNT GPUs"
fi

vllm serve "${VLLM_ARGS[@]}" > /tmp/vllm.log 2>&1 &
echo $! > "$PIDDIR/vllm.pid"
log "vLLM starting (PID: $(cat "$PIDDIR/vllm.pid"))"

# Wait for vLLM health endpoint
echo -n "Waiting for model to load"
TIMEOUT=180  # 15 minutes max (checks every 5s)
for i in $(seq 1 $TIMEOUT); do
    if curl -s "http://localhost:$VLLM_PORT/health" > /dev/null 2>&1; then
        echo ""
        log "vLLM is ready!"
        break
    fi
    if ! kill -0 "$(cat "$PIDDIR/vllm.pid")" 2>/dev/null; then
        echo ""
        echo -e "${RED}vLLM process died. Last 30 lines of log:${NC}"
        tail -30 /tmp/vllm.log
        err "vLLM failed to start. Check /tmp/vllm.log"
    fi
    if [ "$i" -eq $TIMEOUT ]; then
        echo ""
        err "vLLM timed out after 15 minutes. Check: tail -f /tmp/vllm.log"
    fi
    echo -n "."
    sleep 5
done

# --- Start backend (serves frontend from static/) ---
step "Starting DocGemma"

cd "$WORKDIR/docgemma-connect"
export DOCGEMMA_ENDPOINT="http://localhost:$VLLM_PORT"
export DOCGEMMA_API_KEY="token"
export DOCGEMMA_MODEL="$DOCGEMMA_MODEL"

uv run uvicorn docgemma.api.main:app \
    --host 0.0.0.0 \
    --port "$APP_PORT" \
    > /tmp/docgemma.log 2>&1 &
echo $! > "$PIDDIR/docgemma.pid"

sleep 3

if ! kill -0 "$(cat "$PIDDIR/docgemma.pid")" 2>/dev/null; then
    echo -e "${RED}Last 20 lines of log:${NC}"
    tail -20 /tmp/docgemma.log
    err "DocGemma failed to start. Check: tail -f /tmp/docgemma.log"
fi

# --- Generate access URL ---
APP_URL=$(get_access_url "$ENVIRONMENT" "$APP_PORT")
VLLM_URL=$(get_access_url "$ENVIRONMENT" "$VLLM_PORT")

# --- Print access info ---
echo ""
echo -e "${GREEN}---------------------------------------------------------------${NC}"
echo -e "${GREEN}  DocGemma is live!${NC}"
echo -e "${GREEN}---------------------------------------------------------------${NC}"
echo -e "  Environment: ${CYAN}${ENVIRONMENT}${NC}"
echo -e "  GPU:         ${CYAN}${GPU_COUNT}x ${GPU_NAME}${NC}"
echo -e "  Model:       ${CYAN}${DOCGEMMA_MODEL}${NC}"
echo -e "${GREEN}---------------------------------------------------------------${NC}"
echo -e "  App:       ${CYAN}${APP_URL}${NC}"
echo -e "  vLLM API:  ${CYAN}${VLLM_URL}${NC}"
echo -e "${GREEN}---------------------------------------------------------------${NC}"
echo -e "  Logs:"
echo -e "    tail -f /tmp/vllm.log"
echo -e "    tail -f /tmp/docgemma.log"
echo -e "${GREEN}---------------------------------------------------------------${NC}"
echo -e "  Stop: ${YELLOW}Ctrl+C${NC}"
echo ""

case "$ENVIRONMENT" in
    vastai)
        warn "Vast.ai: Make sure ports $APP_PORT and $VLLM_PORT are exposed"
        ;;
    aws)
        warn "AWS: Ensure security group allows inbound on ports $APP_PORT and $VLLM_PORT"
        ;;
    gcp)
        warn "GCP: Ensure firewall rules allow inbound on ports $APP_PORT and $VLLM_PORT"
        ;;
    azure)
        warn "Azure: Ensure NSG allows inbound on ports $APP_PORT and $VLLM_PORT"
        ;;
esac

# Keep script alive, follow logs
tail -f /tmp/vllm.log /tmp/docgemma.log
