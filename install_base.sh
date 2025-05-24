#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $*"; }

USER_HOME="/home/vastai"
WORKSPACE="/workspace"
cd "$WORKSPACE"

# --- Make sure minimal tools are present (should already be in AI Dock images) ---
which git  || { log_error "git not found"; exit 1; }
which npm  || { log_error "npm not found"; exit 1; }
which wget || { log_error "wget not found"; exit 1; }
which pip  || { log_error "pip not found"; exit 1; }

# -- ComfyUI (via comfy-cli, system Python) --
if [[ ! -d "$WORKSPACE/comfy" ]]; then
  log_info "Installing ComfyUI at $WORKSPACE/comfy…"
  pip install --user --upgrade pip
  pip install --user comfy-cli
  ~/.local/bin/comfy --workspace="$WORKSPACE/comfy" install
  ~/.local/bin/comfy --install-completion
else
  log_info "ComfyUI already installed."
fi

# -- SillyTavern --
if [[ ! -d "$WORKSPACE/SillyTavern" ]]; then
  log_info "Cloning SillyTavern…"
  git clone https://github.com/SillyTavern/SillyTavern -b release "$WORKSPACE/SillyTavern"
  cd "$WORKSPACE/SillyTavern"
  npm install
  cd "$WORKSPACE"
else
  log_info "SillyTavern already installed."
fi

# -- KoboldCpp --
if [[ ! -f "$WORKSPACE/koboldcpp/koboldcpp-linux-x64-cuda1210" ]]; then
  log_info "Setting up KoboldCpp…"
  mkdir -p "$WORKSPACE/koboldcpp"
  wget -O "$WORKSPACE/koboldcpp/koboldcpp-linux-x64-cuda1210" \
    https://github.com/LostRuins/koboldcpp/releases/download/v1.91/koboldcpp-linux-x64-cuda1210
  chmod +x "$WORKSPACE/koboldcpp/koboldcpp-linux-x64-cuda1210"
else
  log_info "KoboldCPP binary already present."
fi

# -- Model Downloads (Batch) --
MODEL_DIR="$WORKSPACE/PresetModels/base_models"
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
        log_info "Downloading $FILE_NAME"
        wget -q --show-progress -O "$MODEL_DIR/$FILE_NAME" "$URL"
    else
        log_info "$FILE_NAME already exists."
    fi
done

log_info "All done! ComfyUI, SillyTavern, KoboldCpp, and base models ready in $WORKSPACE."
