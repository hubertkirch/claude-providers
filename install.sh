#!/bin/bash

# Claude Providers Installer
# https://github.com/hubertkirch/claude-providers
#
# Install: curl -sSL https://raw.githubusercontent.com/hubertkirch/claude-providers/main/install.sh | bash
# Or:      bash install.sh
#
# This script sets up Claude Code to work with different LLM providers:
# - GLM (z.ai)
# - MiniMax
# - OpenRouter
# - LM Studio (local, via litellm proxy)
# - Llama.cpp (local, via litellm proxy)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Version
VERSION="1.0.0"

# Configuration
CONFIG_DIR="$HOME/.claude-configs"
LMSTUDIO_PROXY_DIR="$HOME/.claude-lmstudio-proxy"
LLAMACPP_PROXY_DIR="$HOME/.claude-llamacpp-proxy"

# Print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Header
print_header() {
    echo ""
    print_color "$BLUE" "╔══════════════════════════════════════╗"
    print_color "$BLUE" "║    Claude Providers Installer        ║"
    print_color "$BLUE" "║          Version $VERSION               ║"
    print_color "$BLUE" "╚══════════════════════════════════════╝"
    echo ""
}

# Detect Claude Code installation
detect_claude() {
    local claude_bin=$(which claude 2>/dev/null)

    if [ -z "$claude_bin" ]; then
        print_color "$RED" "❌ Error: Claude Code not found" >&2
        echo "Please install Claude Code first: https://claude.ai/download" >&2
        exit 1
    fi

    print_color "$GREEN" "✓ Found Claude Code at: $claude_bin" >&2
    echo "$claude_bin"  # Only output the path itself
}

# Detect best installation directory
detect_install_dir() {
    local install_dir=""

    # Check if ~/.local/bin is in PATH
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
        install_dir="$HOME/.local/bin"
        print_color "$GREEN" "✓ Using ~/.local/bin (already in PATH)" >&2
    # Check if /usr/local/bin is writable
    elif [[ -w "/usr/local/bin" ]]; then
        install_dir="/usr/local/bin"
        print_color "$GREEN" "✓ Using /usr/local/bin" >&2
    else
        install_dir="$HOME/.local/bin"
        print_color "$YELLOW" "⚠ Using ~/.local/bin (not in PATH)" >&2
        echo "" >&2
        print_color "$YELLOW" "Add to your PATH by adding this to ~/.bashrc or ~/.zshrc:" >&2
        echo '    export PATH="$HOME/.local/bin:$PATH"' >&2
        echo "" >&2
        read -p "Continue anyway? (y/n): " -n 1 -r < /dev/tty
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    # Create directory if it doesn't exist
    mkdir -p "$install_dir"
    echo "$install_dir"  # Only output the path itself
}

# Provider configurations using functions for compatibility
get_provider_name() {
    case "$1" in
        glm) echo "GLM (z.ai)" ;;
        minimax) echo "MiniMax" ;;
        openrouter) echo "OpenRouter" ;;
        lmstudio) echo "LM Studio" ;;
        llamacpp) echo "Llama.cpp" ;;
    esac
}

get_provider_url() {
    case "$1" in
        glm) echo "https://api.z.ai/api/anthropic" ;;
        minimax) echo "https://api.minimax.io/anthropic" ;;
        openrouter) echo "https://openrouter.ai/api" ;;
        lmstudio) echo "http://localhost:4000" ;;  # litellm proxy
        llamacpp) echo "http://localhost:4001" ;;  # litellm proxy (different port)
    esac
}

get_provider_model() {
    case "$1" in
        glm) echo "glm-4.7" ;;
        minimax) echo "MiniMax-M2.1" ;;
        openrouter) echo "" ;;  # OpenRouter doesn't use default models
        lmstudio) echo "" ;;    # Set during installation
        llamacpp) echo "" ;;    # Set during installation
    esac
}

get_provider_timeout() {
    case "$1" in
        glm) echo "3000000" ;;
        minimax) echo "120000" ;;
        openrouter) echo "120000" ;;
        lmstudio) echo "3000000" ;;  # Local models can be slow
        llamacpp) echo "3000000" ;;  # Local models can be slow
    esac
}

get_provider_description() {
    case "$1" in
        glm) echo "GLM-4 from z.ai - Fast and efficient" ;;
        minimax) echo "MiniMax AI - Good for specialized tasks" ;;
        openrouter) echo "Access multiple models through one API" ;;
        lmstudio) echo "Local LM Studio models via litellm proxy" ;;
        llamacpp) echo "Local llama.cpp server via litellm proxy" ;;
    esac
}

# Setup litellm proxy for LM Studio (just creates files, no install yet)
setup_lmstudio_proxy() {
    print_color "$BLUE" "Setting up litellm proxy directory..."

    # Check for poetry
    if ! command -v poetry &> /dev/null; then
        print_color "$RED" "Poetry is required for LM Studio support."
        echo "Install it with: curl -sSL https://install.python-poetry.org | python3 -"
        return 1
    fi

    # Create proxy directory
    mkdir -p "$LMSTUDIO_PROXY_DIR"

    # Create pyproject.toml
    cat > "$LMSTUDIO_PROXY_DIR/pyproject.toml" <<'EOF'
[project]
name = "litellm-proxy"
version = "0.1.0"
description = "LiteLLM proxy for Claude Code to LM Studio"
requires-python = ">=3.10"

[tool.poetry]
name = "litellm-proxy"
version = "0.1.0"
description = "LiteLLM proxy for Claude Code to LM Studio"
authors = ["claude-providers"]

[tool.poetry.dependencies]
python = "^3.10"
litellm = {version = ">=1.80.16,<2.0.0", extras = ["proxy"]}

[build-system]
requires = ["poetry-core>=2.0.0,<3.0.0"]
build-backend = "poetry.core.masonry.api"
EOF

    print_color "$GREEN" "Proxy directory created at $LMSTUDIO_PROXY_DIR"
    print_color "$YELLOW" "Note: Dependencies will be installed on first run"
}

# Install LM Studio provider (special handling)
install_lmstudio() {
    local claude_bin=$1
    local install_dir=$2

    print_color "$BLUE" "\nInstalling LM Studio provider..."
    echo "$(get_provider_description "lmstudio")"
    echo ""

    # Get LM Studio address
    print_color "$YELLOW" "LM Studio API address"
    echo "This is where LM Studio is running (default: http://localhost:1234/v1)"
    read -p "Enter LM Studio address [http://localhost:1234/v1]: " lmstudio_url < /dev/tty
    lmstudio_url="${lmstudio_url:-http://localhost:1234/v1}"
    print_color "$GREEN" "Using: $lmstudio_url"
    echo ""

    # Setup the proxy directory (no install yet)
    setup_lmstudio_proxy || return 1

    # Create the wrapper script
    local script_path="$install_dir/claude-lmstudio"
    local proxy_port=4000

    cat > "$script_path" <<EOF
#!/usr/bin/env bash
# Claude instance: lmstudio (via litellm proxy)
# Generated by claude-providers installer v$VERSION
# Date: $(date)

PROXY_PORT=$proxy_port
PROXY_DIR="$LMSTUDIO_PROXY_DIR"
PROXY_LOG="\$PROXY_DIR/proxy.log"
CLAUDE_BIN="$claude_bin"

# LM Studio API base
LMSTUDIO_API_BASE="\${LMSTUDIO_API_BASE:-$lmstudio_url}"

# Parse --model flag (required)
MODEL=""
ARGS=()
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --model)
            MODEL="\$2"
            shift 2
            ;;
        --model=*)
            MODEL="\${1#*=}"
            shift
            ;;
        *)
            ARGS+=("\$1")
            shift
            ;;
    esac
done

# Model is required
if [ -z "\$MODEL" ]; then
    echo "Error: LM Studio requires --model parameter"
    echo ""
    echo "Usage: claude-lmstudio --model 'model-name' [other args]"
    echo ""
    echo "The model name should match a model loaded in LM Studio."
    echo "Example: claude-lmstudio --model devstral-small-2-24b-instruct-2512"
    exit 1
fi

# Install dependencies on first run
if [ ! -f "\$PROXY_DIR/.installed" ]; then
    echo "First run: Installing litellm dependencies..."
    cd "\$PROXY_DIR"
    if ! poetry install --quiet 2>/dev/null; then
        poetry install
    fi
    touch "\$PROXY_DIR/.installed"
fi

# Generate litellm config for the selected model
generate_config() {
    cat > "\$PROXY_DIR/config.yaml" << EOFCONFIG
model_list:
  - model_name: \$MODEL
    litellm_params:
      model: openai/\$MODEL
      api_base: \$LMSTUDIO_API_BASE
      api_key: lmstudio

general_settings:
  master_key: lmstudio

litellm_settings:
  drop_params: true
EOFCONFIG
}

# Function to restart proxy with new config
restart_proxy() {
    echo "Restarting litellm proxy with model: \$MODEL"
    if [ -f "\$PROXY_DIR/proxy.pid" ]; then
        kill "\$(cat "\$PROXY_DIR/proxy.pid")" 2>/dev/null
        sleep 1
    fi
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"
}

# Check if proxy is already running
if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
    echo "Starting litellm proxy with model: \$MODEL"
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"

    # Wait for proxy to be ready (max 30 seconds)
    for i in {1..30}; do
        if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
            echo "Proxy started (PID: \$PROXY_PID)"
            break
        fi
        sleep 1
    done

    if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
        echo "Error: Proxy failed to start. Check \$PROXY_LOG"
        exit 1
    fi
else
    # Proxy is running - check if we need to restart with different model
    CURRENT_CONFIG_MODEL=\$(grep "model_name:" "\$PROXY_DIR/config.yaml" 2>/dev/null | head -1 | awk '{print \$NF}')
    if [ "\$CURRENT_CONFIG_MODEL" != "\$MODEL" ]; then
        restart_proxy
        # Wait for proxy to be ready
        for i in {1..30}; do
            if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
                echo "Proxy restarted (PID: \$PROXY_PID)"
                break
            fi
            sleep 1
        done
    else
        echo "Using existing proxy with model: \$MODEL"
    fi
fi

export CLAUDE_HOME="\$HOME/.claude-lmstudio"
export ANTHROPIC_AUTH_TOKEN="lmstudio"
export ANTHROPIC_BASE_URL="http://localhost:\$PROXY_PORT"
export API_TIMEOUT_MS="$(get_provider_timeout "lmstudio")"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export ANTHROPIC_MODEL="\$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="\$MODEL"

exec "\$CLAUDE_BIN" "\${ARGS[@]}"
EOF

    chmod 700 "$script_path"
    print_color "$GREEN" "Created: claude-lmstudio"

    # Create auto version
    local auto_script_path="$install_dir/claude-lmstudio-auto"

    cat > "$auto_script_path" <<EOF
#!/usr/bin/env bash
# Claude instance: lmstudio (auto-approval, via litellm proxy)
# Generated by claude-providers installer v$VERSION
# Date: $(date)

PROXY_PORT=$proxy_port
PROXY_DIR="$LMSTUDIO_PROXY_DIR"
PROXY_LOG="\$PROXY_DIR/proxy.log"
CLAUDE_BIN="$claude_bin"

# LM Studio API base
LMSTUDIO_API_BASE="\${LMSTUDIO_API_BASE:-$lmstudio_url}"

# Parse --model flag (required)
MODEL=""
ARGS=()
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --model)
            MODEL="\$2"
            shift 2
            ;;
        --model=*)
            MODEL="\${1#*=}"
            shift
            ;;
        *)
            ARGS+=("\$1")
            shift
            ;;
    esac
done

# Model is required
if [ -z "\$MODEL" ]; then
    echo "Error: LM Studio requires --model parameter"
    echo ""
    echo "Usage: claude-lmstudio-auto --model 'model-name' [other args]"
    echo ""
    echo "The model name should match a model loaded in LM Studio."
    echo "Example: claude-lmstudio-auto --model devstral-small-2-24b-instruct-2512"
    exit 1
fi

# Install dependencies on first run
if [ ! -f "\$PROXY_DIR/.installed" ]; then
    echo "First run: Installing litellm dependencies..."
    cd "\$PROXY_DIR"
    if ! poetry install --quiet 2>/dev/null; then
        poetry install
    fi
    touch "\$PROXY_DIR/.installed"
fi

# Generate litellm config for the selected model
generate_config() {
    cat > "\$PROXY_DIR/config.yaml" << EOFCONFIG
model_list:
  - model_name: \$MODEL
    litellm_params:
      model: openai/\$MODEL
      api_base: \$LMSTUDIO_API_BASE
      api_key: lmstudio

general_settings:
  master_key: lmstudio

litellm_settings:
  drop_params: true
EOFCONFIG
}

# Function to restart proxy with new config
restart_proxy() {
    echo "Restarting litellm proxy with model: \$MODEL"
    if [ -f "\$PROXY_DIR/proxy.pid" ]; then
        kill "\$(cat "\$PROXY_DIR/proxy.pid")" 2>/dev/null
        sleep 1
    fi
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"
}

# Check if proxy is already running
if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
    echo "Starting litellm proxy with model: \$MODEL"
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"

    # Wait for proxy to be ready (max 30 seconds)
    for i in {1..30}; do
        if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
            echo "Proxy started (PID: \$PROXY_PID)"
            break
        fi
        sleep 1
    done

    if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
        echo "Error: Proxy failed to start. Check \$PROXY_LOG"
        exit 1
    fi
else
    # Proxy is running - check if we need to restart with different model
    CURRENT_CONFIG_MODEL=\$(grep "model_name:" "\$PROXY_DIR/config.yaml" 2>/dev/null | head -1 | awk '{print \$NF}')
    if [ "\$CURRENT_CONFIG_MODEL" != "\$MODEL" ]; then
        restart_proxy
        # Wait for proxy to be ready
        for i in {1..30}; do
            if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
                echo "Proxy restarted (PID: \$PROXY_PID)"
                break
            fi
            sleep 1
        done
    else
        echo "Using existing proxy with model: \$MODEL"
    fi
fi

export CLAUDE_HOME="\$HOME/.claude-lmstudio"
export ANTHROPIC_AUTH_TOKEN="lmstudio"
export ANTHROPIC_BASE_URL="http://localhost:\$PROXY_PORT"
export API_TIMEOUT_MS="$(get_provider_timeout "lmstudio")"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export ANTHROPIC_MODEL="\$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="\$MODEL"

exec "\$CLAUDE_BIN" --dangerously-skip-permissions "\${ARGS[@]}"
EOF

    chmod 700 "$auto_script_path"
    print_color "$GREEN" "Created: claude-lmstudio-auto"

    # Save configuration
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/lmstudio.json" <<EOF
{
  "provider": "lmstudio",
  "installed": true,
  "version": "$VERSION",
  "created": "$(date -Iseconds)",
  "install_dir": "$install_dir",
  "script_path": "$script_path",
  "auto_script_path": "$auto_script_path",
  "lmstudio_url": "$lmstudio_url"
}
EOF

    print_color "$GREEN" "Installation complete!"
    echo ""
    print_color "$BLUE" "Usage:"
    echo "  claude-lmstudio --model 'model-name'       # Specify model from LM Studio"
    echo "  claude-lmstudio-auto --model 'model-name'  # Auto-approval mode"
    echo ""
    print_color "$YELLOW" "Note: Dependencies install on first run, proxy starts automatically"
}

# Setup litellm proxy for Llama.cpp (just creates files, no install yet)
setup_llamacpp_proxy() {
    print_color "$BLUE" "Setting up litellm proxy directory for Llama.cpp..."

    # Check for poetry
    if ! command -v poetry &> /dev/null; then
        print_color "$RED" "Poetry is required for Llama.cpp support."
        echo "Install it with: curl -sSL https://install.python-poetry.org | python3 -"
        return 1
    fi

    # Create proxy directory
    mkdir -p "$LLAMACPP_PROXY_DIR"

    # Create pyproject.toml
    cat > "$LLAMACPP_PROXY_DIR/pyproject.toml" <<'EOF'
[project]
name = "litellm-proxy-llamacpp"
version = "0.1.0"
description = "LiteLLM proxy for Claude Code to Llama.cpp"
requires-python = ">=3.10"

[tool.poetry]
name = "litellm-proxy-llamacpp"
version = "0.1.0"
description = "LiteLLM proxy for Claude Code to Llama.cpp"
authors = ["claude-providers"]

[tool.poetry.dependencies]
python = "^3.10"
litellm = {version = ">=1.80.16,<2.0.0", extras = ["proxy"]}

[build-system]
requires = ["poetry-core>=2.0.0,<3.0.0"]
build-backend = "poetry.core.masonry.api"
EOF

    print_color "$GREEN" "Proxy directory created at $LLAMACPP_PROXY_DIR"
    print_color "$YELLOW" "Note: Dependencies will be installed on first run"
}

# Install Llama.cpp provider (special handling)
install_llamacpp() {
    local claude_bin=$1
    local install_dir=$2

    print_color "$BLUE" "\nInstalling Llama.cpp provider..."
    echo "$(get_provider_description "llamacpp")"
    echo ""

    # Get Llama.cpp server address
    print_color "$YELLOW" "Llama.cpp server API address"
    echo "This is where llama-server is running (default: http://localhost:8080/v1)"
    read -p "Enter Llama.cpp server address [http://localhost:8080/v1]: " llamacpp_url < /dev/tty
    llamacpp_url="${llamacpp_url:-http://localhost:8080/v1}"
    print_color "$GREEN" "Using: $llamacpp_url"
    echo ""

    # Setup the proxy directory (no install yet)
    setup_llamacpp_proxy || return 1

    # Create the wrapper script
    local script_path="$install_dir/claude-llamacpp"
    local proxy_port=4001

    cat > "$script_path" <<EOF
#!/usr/bin/env bash
# Claude instance: llamacpp (via litellm proxy)
# Generated by claude-providers installer v$VERSION
# Date: $(date)

PROXY_PORT=$proxy_port
PROXY_DIR="$LLAMACPP_PROXY_DIR"
PROXY_LOG="\$PROXY_DIR/proxy.log"
CLAUDE_BIN="$claude_bin"

# Llama.cpp server API base
LLAMACPP_API_BASE="\${LLAMACPP_API_BASE:-$llamacpp_url}"

# Parse --model flag (required)
MODEL=""
ARGS=()
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --model)
            MODEL="\$2"
            shift 2
            ;;
        --model=*)
            MODEL="\${1#*=}"
            shift
            ;;
        *)
            ARGS+=("\$1")
            shift
            ;;
    esac
done

# Model is required
if [ -z "\$MODEL" ]; then
    echo "Error: Llama.cpp requires --model parameter"
    echo ""
    echo "Usage: claude-llamacpp --model 'model-name' [other args]"
    echo ""
    echo "The model name should match the model loaded in llama-server."
    echo "Example: claude-llamacpp --model qwen2.5-coder-32b"
    exit 1
fi

# Install dependencies on first run
if [ ! -f "\$PROXY_DIR/.installed" ]; then
    echo "First run: Installing litellm dependencies..."
    cd "\$PROXY_DIR"
    if ! poetry install --quiet 2>/dev/null; then
        poetry install
    fi
    touch "\$PROXY_DIR/.installed"
fi

# Generate litellm config for the selected model
generate_config() {
    cat > "\$PROXY_DIR/config.yaml" << EOFCONFIG
model_list:
  - model_name: \$MODEL
    litellm_params:
      model: openai/\$MODEL
      api_base: \$LLAMACPP_API_BASE
      api_key: llamacpp

general_settings:
  master_key: llamacpp

litellm_settings:
  drop_params: true
EOFCONFIG
}

# Function to restart proxy with new config
restart_proxy() {
    echo "Restarting litellm proxy with model: \$MODEL"
    if [ -f "\$PROXY_DIR/proxy.pid" ]; then
        kill "\$(cat "\$PROXY_DIR/proxy.pid")" 2>/dev/null
        sleep 1
    fi
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"
}

# Check if proxy is already running
if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
    echo "Starting litellm proxy with model: \$MODEL"
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"

    # Wait for proxy to be ready (max 30 seconds)
    for i in {1..30}; do
        if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
            echo "Proxy started (PID: \$PROXY_PID)"
            break
        fi
        sleep 1
    done

    if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
        echo "Error: Proxy failed to start. Check \$PROXY_LOG"
        exit 1
    fi
else
    # Proxy is running - check if we need to restart with different model
    CURRENT_CONFIG_MODEL=\$(grep "model_name:" "\$PROXY_DIR/config.yaml" 2>/dev/null | head -1 | awk '{print \$NF}')
    if [ "\$CURRENT_CONFIG_MODEL" != "\$MODEL" ]; then
        restart_proxy
        # Wait for proxy to be ready
        for i in {1..30}; do
            if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
                echo "Proxy restarted (PID: \$PROXY_PID)"
                break
            fi
            sleep 1
        done
    else
        echo "Using existing proxy with model: \$MODEL"
    fi
fi

export CLAUDE_HOME="\$HOME/.claude-llamacpp"
export ANTHROPIC_AUTH_TOKEN="llamacpp"
export ANTHROPIC_BASE_URL="http://localhost:\$PROXY_PORT"
export API_TIMEOUT_MS="$(get_provider_timeout "llamacpp")"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export ANTHROPIC_MODEL="\$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="\$MODEL"

exec "\$CLAUDE_BIN" "\${ARGS[@]}"
EOF

    chmod 700 "$script_path"
    print_color "$GREEN" "Created: claude-llamacpp"

    # Create auto version
    local auto_script_path="$install_dir/claude-llamacpp-auto"

    cat > "$auto_script_path" <<EOF
#!/usr/bin/env bash
# Claude instance: llamacpp (auto-approval, via litellm proxy)
# Generated by claude-providers installer v$VERSION
# Date: $(date)

PROXY_PORT=$proxy_port
PROXY_DIR="$LLAMACPP_PROXY_DIR"
PROXY_LOG="\$PROXY_DIR/proxy.log"
CLAUDE_BIN="$claude_bin"

# Llama.cpp server API base
LLAMACPP_API_BASE="\${LLAMACPP_API_BASE:-$llamacpp_url}"

# Parse --model flag (required)
MODEL=""
ARGS=()
while [[ \$# -gt 0 ]]; do
    case \$1 in
        --model)
            MODEL="\$2"
            shift 2
            ;;
        --model=*)
            MODEL="\${1#*=}"
            shift
            ;;
        *)
            ARGS+=("\$1")
            shift
            ;;
    esac
done

# Model is required
if [ -z "\$MODEL" ]; then
    echo "Error: Llama.cpp requires --model parameter"
    echo ""
    echo "Usage: claude-llamacpp-auto --model 'model-name' [other args]"
    echo ""
    echo "The model name should match the model loaded in llama-server."
    echo "Example: claude-llamacpp-auto --model qwen2.5-coder-32b"
    exit 1
fi

# Install dependencies on first run
if [ ! -f "\$PROXY_DIR/.installed" ]; then
    echo "First run: Installing litellm dependencies..."
    cd "\$PROXY_DIR"
    if ! poetry install --quiet 2>/dev/null; then
        poetry install
    fi
    touch "\$PROXY_DIR/.installed"
fi

# Generate litellm config for the selected model
generate_config() {
    cat > "\$PROXY_DIR/config.yaml" << EOFCONFIG
model_list:
  - model_name: \$MODEL
    litellm_params:
      model: openai/\$MODEL
      api_base: \$LLAMACPP_API_BASE
      api_key: llamacpp

general_settings:
  master_key: llamacpp

litellm_settings:
  drop_params: true
EOFCONFIG
}

# Function to restart proxy with new config
restart_proxy() {
    echo "Restarting litellm proxy with model: \$MODEL"
    if [ -f "\$PROXY_DIR/proxy.pid" ]; then
        kill "\$(cat "\$PROXY_DIR/proxy.pid")" 2>/dev/null
        sleep 1
    fi
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"
}

# Check if proxy is already running
if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
    echo "Starting litellm proxy with model: \$MODEL"
    generate_config
    cd "\$PROXY_DIR"
    poetry run litellm --config config.yaml --port \$PROXY_PORT --host 0.0.0.0 > "\$PROXY_LOG" 2>&1 &
    PROXY_PID=\$!
    echo \$PROXY_PID > "\$PROXY_DIR/proxy.pid"

    # Wait for proxy to be ready (max 30 seconds)
    for i in {1..30}; do
        if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
            echo "Proxy started (PID: \$PROXY_PID)"
            break
        fi
        sleep 1
    done

    if ! curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
        echo "Error: Proxy failed to start. Check \$PROXY_LOG"
        exit 1
    fi
else
    # Proxy is running - check if we need to restart with different model
    CURRENT_CONFIG_MODEL=\$(grep "model_name:" "\$PROXY_DIR/config.yaml" 2>/dev/null | head -1 | awk '{print \$NF}')
    if [ "\$CURRENT_CONFIG_MODEL" != "\$MODEL" ]; then
        restart_proxy
        # Wait for proxy to be ready
        for i in {1..30}; do
            if curl -s "http://localhost:\$PROXY_PORT/health" > /dev/null 2>&1; then
                echo "Proxy restarted (PID: \$PROXY_PID)"
                break
            fi
            sleep 1
        done
    else
        echo "Using existing proxy with model: \$MODEL"
    fi
fi

export CLAUDE_HOME="\$HOME/.claude-llamacpp"
export ANTHROPIC_AUTH_TOKEN="llamacpp"
export ANTHROPIC_BASE_URL="http://localhost:\$PROXY_PORT"
export API_TIMEOUT_MS="$(get_provider_timeout "llamacpp")"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export ANTHROPIC_MODEL="\$MODEL"
export ANTHROPIC_SMALL_FAST_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_SONNET_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_OPUS_MODEL="\$MODEL"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="\$MODEL"

exec "\$CLAUDE_BIN" --dangerously-skip-permissions "\${ARGS[@]}"
EOF

    chmod 700 "$auto_script_path"
    print_color "$GREEN" "Created: claude-llamacpp-auto"

    # Save configuration
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/llamacpp.json" <<EOF
{
  "provider": "llamacpp",
  "installed": true,
  "version": "$VERSION",
  "created": "$(date -Iseconds)",
  "install_dir": "$install_dir",
  "script_path": "$script_path",
  "auto_script_path": "$auto_script_path",
  "llamacpp_url": "$llamacpp_url"
}
EOF

    print_color "$GREEN" "Installation complete!"
    echo ""
    print_color "$BLUE" "Usage:"
    echo "  claude-llamacpp --model 'model-name'       # Specify model from llama-server"
    echo "  claude-llamacpp-auto --model 'model-name'  # Auto-approval mode"
    echo ""
    print_color "$YELLOW" "Note: Dependencies install on first run, proxy starts automatically"
    echo ""
    print_color "$BLUE" "Starting llama-server:"
    echo "  llama-server -m /path/to/model.gguf --port 8080"
}

# Install a provider
install_provider() {
    local provider=$1
    local claude_bin=$2
    local install_dir=$3
    local api_key=""

    print_color "$BLUE" "\n📦 Installing $(get_provider_name "$provider")..."
    echo "$(get_provider_description "$provider")"

    # Get API key
    echo ""
    read -s -p "Enter your $(get_provider_name "$provider") API key: " api_key < /dev/tty
    echo ""  # New line after password entry

    if [ -z "$api_key" ]; then
        print_color "$RED" "❌ API key cannot be empty"
        return 1
    fi

    # Confirm API key was entered
    print_color "$GREEN" "✓ API key received (${#api_key} characters)"
    echo ""
    read -p "Press Enter to continue with installation... " < /dev/tty
    echo ""

    # Create standard version
    local script_path="$install_dir/claude-$provider"

    cat > "$script_path" <<EOF
#!/bin/bash
# Claude instance: $provider
# Generated by claude-providers installer v$VERSION
# Date: $(date)

CLAUDE_BIN="$claude_bin"

export CLAUDE_HOME="\$HOME/.claude-$provider"
export ANTHROPIC_AUTH_TOKEN="$api_key"
export ANTHROPIC_BASE_URL="$(get_provider_url "$provider")"
export API_TIMEOUT_MS="$(get_provider_timeout "$provider")"
EOF

    # Add model mappings for non-OpenRouter providers
    if [ "$provider" != "openrouter" ]; then
        cat >> "$script_path" <<EOF
export ANTHROPIC_DEFAULT_OPUS_MODEL="$(get_provider_model "$provider")"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$(get_provider_model "$provider")"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$(get_provider_model "$provider")"
EOF
    else
        # OpenRouter needs empty API key and model check
        cat >> "$script_path" <<EOF
export ANTHROPIC_API_KEY=""  # Must be empty for OpenRouter

# OpenRouter requires explicit model selection
if [[ ! " \$* " =~ " --model " ]]; then
    echo "Error: OpenRouter requires --model parameter"
    echo ""
    echo "Usage: claude-openrouter --model 'model-name' [other args]"
    echo ""
    echo "Popular models:"
    echo "  anthropic/claude-3.5-sonnet"
    echo "  openai/gpt-4-turbo"
    echo "  google/gemini-pro"
    echo "  meta-llama/llama-3.1-70b"
    echo ""
    echo "See https://openrouter.ai/models for full list"
    exit 1
fi
EOF
    fi

    # Complete the standard script
    cat >> "$script_path" <<EOF

exec "\$CLAUDE_BIN" "\$@"
EOF

    chmod 700 "$script_path"
    print_color "$GREEN" "✓ Created: claude-$provider"

    # Create auto version
    local auto_script_path="$install_dir/claude-$provider-auto"

    cat > "$auto_script_path" <<EOF
#!/bin/bash
# Claude instance: $provider (auto-approval)
# Generated by claude-providers installer v$VERSION
# Date: $(date)

CLAUDE_BIN="$claude_bin"

export CLAUDE_HOME="\$HOME/.claude-$provider"
export ANTHROPIC_AUTH_TOKEN="$api_key"
export ANTHROPIC_BASE_URL="$(get_provider_url "$provider")"
export API_TIMEOUT_MS="$(get_provider_timeout "$provider")"
EOF

    # Add model mappings for non-OpenRouter providers
    if [ "$provider" != "openrouter" ]; then
        cat >> "$auto_script_path" <<EOF
export ANTHROPIC_DEFAULT_OPUS_MODEL="$(get_provider_model "$provider")"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$(get_provider_model "$provider")"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$(get_provider_model "$provider")"
EOF
    else
        cat >> "$auto_script_path" <<EOF
export ANTHROPIC_API_KEY=""  # Must be empty for OpenRouter

# OpenRouter requires explicit model selection
if [[ ! " \$* " =~ " --model " ]]; then
    echo "Error: OpenRouter requires --model parameter (even in auto mode)"
    echo "Usage: claude-openrouter-auto --model 'model-name' [other args]"
    exit 1
fi
EOF
    fi

    # Complete the auto script
    cat >> "$auto_script_path" <<EOF

exec "\$CLAUDE_BIN" --dangerously-skip-permissions "\$@"
EOF

    chmod 700 "$auto_script_path"
    print_color "$GREEN" "✓ Created: claude-$provider-auto"

    # Save configuration (for tracking only, no API keys)
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_DIR/$provider.json" <<EOF
{
  "provider": "$provider",
  "installed": true,
  "version": "$VERSION",
  "created": "$(date -Iseconds)",
  "install_dir": "$install_dir",
  "script_path": "$script_path",
  "auto_script_path": "$auto_script_path"
}
EOF

    print_color "$GREEN" "✓ Installation complete!"

    # Show usage
    echo ""
    print_color "$BLUE" "Usage:"
    if [ "$provider" == "openrouter" ]; then
        echo "  claude-$provider --model 'anthropic/claude-3.5-sonnet' \"Your prompt\""
        echo "  claude-$provider-auto --model 'openai/gpt-4-turbo' -p \"Your prompt\""
    else
        echo "  claude-$provider \"Your prompt\""
        echo "  claude-$provider-auto -p \"Your prompt\""
    fi
}

# List installed providers
list_providers() {
    print_color "$BLUE" "\n📋 Installed providers:"
    echo ""

    if [ ! -d "$CONFIG_DIR" ]; then
        echo "No providers installed yet."
        return
    fi

    local found=false
    for config in "$CONFIG_DIR"/*.json; do
        if [ -f "$config" ]; then
            found=true
            local provider=$(basename "$config" .json)
            local script_path=$(grep -o '"script_path": "[^"]*' "$config" | cut -d'"' -f4)

            if [ -f "$script_path" ]; then
                print_color "$GREEN" "• claude-$provider"
                echo "  Location: $script_path"
                echo "  Auto version: ${script_path}-auto"
                echo ""
            fi
        fi
    done

    if [ "$found" = false ]; then
        echo "No providers installed yet."
    fi
}

# Remove a provider
remove_provider() {
    local provider=$1

    if [ ! -f "$CONFIG_DIR/$provider.json" ]; then
        print_color "$RED" "Provider '$provider' not installed"
        return 1
    fi

    local install_dir=$(grep -o '"install_dir": "[^"]*' "$CONFIG_DIR/$provider.json" | cut -d'"' -f4)

    print_color "$YELLOW" "Removing claude-$provider..."

    rm -f "$install_dir/claude-$provider"
    rm -f "$install_dir/claude-$provider-auto"
    rm -f "$CONFIG_DIR/$provider.json"

    print_color "$GREEN" "✓ Removed claude-$provider"
}

# Interactive menu
interactive_menu() {
    local claude_bin=$1
    local install_dir=$2

    while true; do
        echo ""
        print_color "$BLUE" "Select provider to install:"
        echo "1) GLM (z.ai)"
        echo "2) MiniMax"
        echo "3) OpenRouter"
        echo "4) LM Studio (local)"
        echo "5) Llama.cpp (local)"
        echo "6) Install ALL (cloud providers)"
        echo "7) List installed"
        echo "8) Remove provider"
        echo "9) Exit"
        echo ""
        read -p "Choice (1-9): " choice < /dev/tty

        case $choice in
            1) install_provider "glm" "$claude_bin" "$install_dir" ;;
            2) install_provider "minimax" "$claude_bin" "$install_dir" ;;
            3) install_provider "openrouter" "$claude_bin" "$install_dir" ;;
            4) install_lmstudio "$claude_bin" "$install_dir" ;;
            5) install_llamacpp "$claude_bin" "$install_dir" ;;
            6)
                install_provider "glm" "$claude_bin" "$install_dir"
                install_provider "minimax" "$claude_bin" "$install_dir"
                install_provider "openrouter" "$claude_bin" "$install_dir"
                ;;
            7) list_providers ;;
            8)
                read -p "Provider to remove (glm/minimax/openrouter/lmstudio/llamacpp): " provider < /dev/tty
                remove_provider "$provider"
                ;;
            9)
                print_color "$GREEN" "Goodbye!"
                exit 0
                ;;
            *)
                print_color "$RED" "Invalid choice"
                ;;
        esac
    done
}

# Main execution
main() {
    print_header

    # Detect Claude Code
    local claude_bin=$(detect_claude)

    # Detect installation directory
    local install_dir=$(detect_install_dir)

    # Check command line arguments
    case "${1:-}" in
        glm|minimax|openrouter)
            # Quick install single provider
            if [ -n "${2:-}" ]; then
                # API key provided
                install_provider "$1" "$claude_bin" "$install_dir" <<< "$2"
            else
                install_provider "$1" "$claude_bin" "$install_dir"
            fi
            ;;
        lmstudio)
            # LM Studio has special installation
            install_lmstudio "$claude_bin" "$install_dir"
            ;;
        llamacpp)
            # Llama.cpp has special installation
            install_llamacpp "$claude_bin" "$install_dir"
            ;;
        all)
            # Install all cloud providers (local providers require interactive setup)
            install_provider "glm" "$claude_bin" "$install_dir"
            install_provider "minimax" "$claude_bin" "$install_dir"
            install_provider "openrouter" "$claude_bin" "$install_dir"
            ;;
        list)
            list_providers
            ;;
        remove)
            if [ -n "${2:-}" ]; then
                remove_provider "$2"
            else
                print_color "$RED" "Usage: $0 remove <provider>"
            fi
            ;;
        help|--help|-h)
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  glm [API_KEY]       Install GLM provider"
            echo "  minimax [API_KEY]   Install MiniMax provider"
            echo "  openrouter [KEY]    Install OpenRouter provider"
            echo "  lmstudio            Install LM Studio provider (local)"
            echo "  llamacpp            Install Llama.cpp provider (local)"
            echo "  all                 Install all cloud providers"
            echo "  list                List installed providers"
            echo "  remove <provider>   Remove a provider"
            echo "  help                Show this help"
            echo ""
            echo "Interactive mode:"
            echo "  $0                  Start interactive installation"
            ;;
        "")
            # Interactive mode
            interactive_menu "$claude_bin" "$install_dir"
            ;;
        *)
            print_color "$RED" "Unknown command: $1"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

# Run main
main "$@"