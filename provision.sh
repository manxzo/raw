#!/bin/bash
set -euo pipefail

# Install system dependencies as root
apt update
apt install -y git curl wget build-essential libssl-dev zlib1g-dev \
    libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
    libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev aria2 python3-pip python3-venv nodejs npm

# Now do all setup as the desktop user (`vastai`)
sudo -u user -H bash <<'EOF'
set -euo pipefail

export HOME="/home/user"
export BASEDIR="$HOME"
export VENV="$BASEDIR/venv"
export MODELDIR="$BASEDIR/PresetModels/full_models"
export COMFYDIR="$BASEDIR/comfy"
export SILLYDIR="$BASEDIR/SillyTavern"
export KOBOLDDIR="$BASEDIR/koboldcpp"
mkdir -p "$MODELDIR"

log_info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }

# Python venv setup (user mode)
if [[ ! -d "$VENV" ]]; then
    log_info "Creating Python venv at $VENV"
    python3 -m venv "$VENV"
fi
source "$VENV/bin/activate"
pip install --upgrade pip

# Install ComfyUI CLI and workspace
if [[ ! -d "$COMFYDIR" ]]; then
    log_info "Installing ComfyUI via comfy-cli"
    pip install comfy-cli
    comfy --workspace="$COMFYDIR" install
    comfy --install-completion
else
    log_info "ComfyUI already installed."
fi

# Install SillyTavern
if [[ ! -d "$SILLYDIR" ]]; then
    log_info "Cloning SillyTavern"
    git clone https://github.com/SillyTavern/SillyTavern -b release "$SILLYDIR"
    cd "$SILLYDIR"
    npm install
else
    log_info "SillyTavern already installed."
fi

# Download KoboldCpp binary
if [[ ! -f "$KOBOLDDIR/koboldcpp-linux-x64-cuda1210" ]]; then
    log_info "Downloading KoboldCpp"
    mkdir -p "$KOBOLDDIR"
    wget -O "$KOBOLDDIR/koboldcpp-linux-x64-cuda1210" \
      https://github.com/LostRuins/koboldcpp/releases/download/v1.91/koboldcpp-linux-x64-cuda1210
    chmod +x "$KOBOLDDIR/koboldcpp-linux-x64-cuda1210"
else
    log_info "KoboldCpp binary already present."
fi

# Download all models
MODEL_URLS=(
  "https://huggingface.co/mradermacher/distilgpt2-stable-diffusion-v2-i1-GGUF/resolve/main/distilgpt2-stable-diffusion-v2.i1-Q6_K.gguf"
  "https://huggingface.co/mradermacher/EraX-VL-2B-V1.5-i1-GGUF/resolve/main/EraX-VL-2B-V1.5.i1-Q6_K.gguf"
  "https://civitai.com/api/download/models/1699918?type=Model&format=SafeTensor&size=pruned&fp=fp16&token=33aff9b39ae63b68db212418031f9ce1"
  "https://huggingface.co/nidum/Nidum-Gemma-3-27B-it-Uncensored-GGUF/resolve/main/model-Q6_K.gguf"
)
for URL in "${MODEL_URLS[@]}"; do
  FILE_NAME=$(basename "${URL%%\?*}")
  if [[ ! -f "$MODELDIR/$FILE_NAME" ]]; then
    log_info "Downloading $FILE_NAME"
    aria2c -x 16 -s 16 -d "$MODELDIR" -o "$FILE_NAME" "$URL" || log_warn "Download failed: $URL"
  else
    log_info "$FILE_NAME already exists. Skipping."
  fi
done

log_info "User-mode provisioning complete! Everything is in $BASEDIR"
EOF
