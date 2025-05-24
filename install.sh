#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ===============================================
# Robust User-Only Installer for:
#   - ComfyUI (via comfy-cli)
#   - SillyTavern
#   - KoboldCPP
#   - Model Downloads (Aria2c)
# ===============================================

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }
fail()      { log_error "$*"; exit 1; }

retry() {
  local desc="$1"; shift
  local tries=0
  until "$@"; do
    ((tries++))
    log_warn "Attempt #$tries: $desc"
    [[ $tries -lt 3 ]] || {
      read -rp "Failed: $desc. Retry? (y/N): " yn
      [[ $yn =~ ^[Yy]$ ]] && tries=0 || { log_error "Giving up: $desc"; return 1; }
    }
    sleep 1
  done
  log_info "Success: $desc"
}

install_deps() {
  log_info "Installing system dependencies…"
  sudo apt update
  sudo apt install -y git curl wget build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev aria2 || fail "Apt install failed"
}

install_pyenv() {
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PYENV_ROOT/bin:$PATH"
  [[ -d "$PYENV_ROOT" ]] && { log_info "pyenv already installed."; return 0; }
  log_info "Installing pyenv to $PYENV_ROOT…"
  curl -fsSL https://pyenv.run | bash
  export PATH="$PYENV_ROOT/bin:$PATH"
}

setup_python() {
  eval "$("$HOME/.pyenv/bin/pyenv" init -)"
  export PATH="$HOME/.pyenv/bin:$PATH"
  if ! pyenv versions | grep -q 3.11.6; then
    log_info "Installing Python 3.11.6 via pyenv…"
    pyenv install 3.11.6
  fi
  pyenv global 3.11.6
  PY311=$(pyenv which python3)
  log_info "Python 3.11.6 installed at: $PY311"
}

setup_venv() {
  [[ -d "$HOME/venv" ]] && log_info "venv already exists." || {
    log_info "Creating Python venv in $HOME/venv…"
    "$(pyenv which python3)" -m venv "$HOME/venv"
  }
  source "$HOME/venv/bin/activate"
  log_info "Activated venv: $VIRTUAL_ENV"
}

install_python_packages() {
  pip install --upgrade pip
  pip install comfy-cli
}

check_node() {
  if command -v node &>/dev/null; then
    NODEV=$(node -v | cut -c2- | cut -d. -f1)
    if [[ "$NODEV" -ge 22 ]]; then
      log_info "Node.js v$NODEV detected (OK)."
    else
      log_warn "Node.js < v22 detected."
      install_nvm_and_node
    fi
  else
    log_warn "Node.js not found, installing via nvm."
    install_nvm_and_node
  fi
}

install_nvm_and_node() {
  export NVM_DIR="$HOME/.nvm"
  [[ -s "$NVM_DIR/nvm.sh" ]] || curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  nvm install 22
  nvm use 22
}

install_comfy() {
  [[ -d "$HOME/comfy" ]] && { log_info "ComfyUI already installed."; return 0; }
  log_info "Installing ComfyUI at $HOME/comfy…"
  comfy --workspace="$HOME/comfy" install
  comfy --install-completion
}

install_sillytavern() {
  [[ -d "$HOME/SillyTavern" ]] && { log_info "SillyTavern already installed."; return 0; }
  log_info "Cloning SillyTavern…"
  git clone https://github.com/SillyTavern/SillyTavern -b release "$HOME/SillyTavern"
  cd "$HOME/SillyTavern"
  npm install
}

install_koboldcpp() {
  [[ -f "$HOME/koboldcpp/koboldcpp-linux-x64-cuda1210" ]] && { log_info "KoboldCPP binary already present."; return 0; }
  log_info "Setting up KoboldCPP…"
  mkdir -p "$HOME/koboldcpp"
  wget -O "$HOME/koboldcpp/koboldcpp-linux-x64-cuda1210" \
    https://github.com/LostRuins/koboldcpp/releases/download/v1.91/koboldcpp-linux-x64-cuda1210
  chmod +x "$HOME/koboldcpp/koboldcpp-linux-x64-cuda1210"
}

#----- Base Models Download----------
base_models_download() {
local MODEL_DIR="$HOME/PresetModels/base_models"
mkdir -p "$MODEL_DIR"
MODEL_URLS=(
    "https://huggingface.co/mradermacher/distilgpt2-stable-diffusion-v2-i1-GGUF/resolve/main/distilgpt2-stable-diffusion-v2.i1-Q6_K.gguf"
    "https://huggingface.co/mradermacher/EraX-VL-2B-V1.5-i1-GGUF/resolve/main/EraX-VL-2B-V1.5.i1-Q6_K.gguf"
    "https://civitai.com/api/download/models/1699918?type=Model&format=SafeTensor&size=pruned&fp=fp16&token=33aff9b39ae63b68db212418031f9ce1"
    "https://huggingface.co/nidum/Nidum-Gemma-3-27B-it-Uncensored-GGUF/resolve/main/model-Q6_K.gguf"
)
for URL in "${MODEL_URLS[@]}"; do
    FILE_NAME=$(basename "${URL%%\?*}")
    if [[ ! -f "$MODEL_DIR/$FILE_NAME" ]]; then
        echo "[INFO] Downloading $FILE_NAME"
        wget -q --show-progress -O "$MODEL_DIR/$FILE_NAME" "$URL"
    else
        echo "[INFO] $FILE_NAME already exists."
    fi
}

# ---- Interactive Model/File Downloader ----
interactive_download() {
  local TARGET_DIR="$HOME/PresetModels/extra_models"
  mkdir -p "$TARGET_DIR"
  while true; do
    echo ""
    read -rp "Enter direct model/file URL to download (or just ENTER to finish): " URL
    [[ -z "$URL" ]] && break
    aria2c -x 16 -s 16 -d "$TARGET_DIR" "$URL"
    echo "Download complete. Add more URLs or press ENTER to finish."
  done
}


# ---- Main Workflow ----
main() {
  install_deps
  install_pyenv
  setup_python
  setup_venv
  install_python_packages
  check_node
  install_comfy
  install_sillytavern
  install_koboldcpp
  base_models_download
# interactive_download
  log_info "All done! Environment is fully set up."
}

main "$@"
