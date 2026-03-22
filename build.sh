#!/bin/bash
#
# ARISE KERNEL BUILDER v4.1
# Optimized for A225G | Bashrc Integration
#

# --- Visuals ---
cyan='\033[1;36m'
red='\033[1;31m'
green='\033[1;32m'
yellow='\033[1;33m'
nocol='\033[0m'

show_banner() {
    clear
    if command -v figlet &> /dev/null; then
        echo -e "${cyan}"
        figlet -f slant "ARISE"
        figlet -f digital "KERNEL"
        echo -e "${nocol}"
    else
        echo -e "${cyan}---------------------------------------"
        echo "    ARISE KERNEL BUILDER v4.1"
        echo -e "---------------------------------------${nocol}"
    fi
}

# --- Core Configuration ---
SRC="$(pwd)"
OUT_DIR="${SRC}/out"
ANYKERNEL3_DIR="${SRC}/AK"
COMPILATION_LOG="${SRC}/compilation.log"
DATE=$(date +"%Y%m%d-%H%M")

# Build Identity
DEVICE="A225G"
DEFCONFIG="a22x_defconfig"
USER_NAME="Itachi"
HOST_NAME="Konoha"

# Toolchain Path
TOOLCHAIN_DIR="/home/itachi/toolchain"
CLANG_ROOT="${TOOLCHAIN_DIR}/clang/host/linux-x86/clang-r383902"
GCC64_ROOT="${TOOLCHAIN_DIR}/gcc/linux-x86/aarch64/aarch64-linux-android-4.9"

# --- Credential Management ---
check_tg_credentials() {
    # 1. Try to source from current shell (if already exported in .bashrc)
    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        # 2. Manually grep from .bashrc if not in current environment
        BOT_TOKEN=$(grep -Po '(?<=export BOT_TOKEN=).*' ~/.bashrc | tr -d '"' | tr -d "'")
        CHAT_ID=$(grep -Po '(?<=export CHAT_ID=).*' ~/.bashrc | tr -d '"' | tr -d "'")
    fi

    # 3. Try local file if .bashrc failed
    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        if [[ -f "${SRC}/SEND_TO_TG.txt" ]]; then
            source "${SRC}/SEND_TO_TG.txt"
        fi
    fi

    # 4. If still empty, ask the user
    if [[ -z "${BOT_TOKEN}" || -z "${CHAT_ID}" ]]; then
        echo -e "${yellow}>> Telegram credentials not found in .bashrc or local file.${nocol}"
        read -p "Enter Bot Token: " BOT_TOKEN
        read -p "Enter Chat ID: " CHAT_ID
        
        read -p "Would you like to save these to your .bashrc for future use? (y/n): " save_choice
        if [[ "$save_choice" == "y" ]]; then
            echo -e "\n# Telegram Credentials for ARISE" >> ~/.bashrc
            echo "export BOT_TOKEN=\"$BOT_TOKEN\"" >> ~/.bashrc
            echo "export CHAT_ID=\"$CHAT_ID\"" >> ~/.bashrc
            echo -e "${green}>> Credentials saved to ~/.bashrc! Restart your terminal or run 'source ~/.bashrc' later.${nocol}"
        fi
    else
        echo -e "${green}>> Telegram credentials loaded successfully.${nocol}"
    fi
}

# --- Build Logic ---
setup_environment() {
    echo -e "${yellow}>> Preparing Environment...${nocol}"
    
    if [ ! -d "$CLANG_ROOT" ] || [ ! -d "$GCC64_ROOT" ]; then
        echo -e "${red}>> Error: Toolchain directory not found at $TOOLCHAIN_DIR${nocol}"
        exit 1
    fi

    export PATH="${CLANG_ROOT}/bin:${GCC64_ROOT}/bin:${PATH}"
    export KBUILD_BUILD_USER="$USER_NAME"
    export KBUILD_BUILD_HOST="$HOST_NAME"
    
    rm -rf "$OUT_DIR" "$COMPILATION_LOG" *.zip
    mkdir -p "$OUT_DIR"
}

send_telegram() {
    local file="$1"
    local msg="$2"
    # Silent upload to avoid cluttering terminal
    curl -s -F document=@"$file" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}&caption=${msg}&parse_mode=HTML" > /dev/null
}

handle_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo -e "\n${red}!! BUILD FAILED !!${nocol}"
        tail -n 20 "$COMPILATION_LOG"
        send_telegram "$COMPILATION_LOG" "❌ <b>Build Failed!</b>%0A<b>Device:</b> $DEVICE"
    else
        echo -e "${green}>> Build successful!${nocol}"
        COMMIT=$(git log -1 --format=%s)
        CAPTION="🚀 <b>ARISE Success!</b>%0A<b>Time:</b> $BUILD_TIME%0A<b>Commit:</b> $COMMIT"
        send_telegram "$FINAL_ZIP" "$CAPTION"
    fi
}
trap handle_exit EXIT

build_kernel() {
    show_banner
    check_tg_credentials
    setup_environment
    
    echo -e "${blue}>> Starting Build for $DEVICE...${nocol}"
    START=$(date +"%s")

    # Generate Config
    make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG" 2>&1 | tee "$COMPILATION_LOG"

    # Compile
    make -j$(nproc --all) O="$OUT_DIR" \
        ARCH=arm64 \
        CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CONFIG_NO_ERROR_ON_MISMATCH=y 2>&1 | tee -a "$COMPILATION_LOG"

    END=$(date +"%s")
    DIFF=$((END - START))
    BUILD_TIME="$((DIFF / 60))m $((DIFF % 60))s"
}

package_kernel() {
    IMAGE="$OUT_DIR/arch/arm64/boot/Image.gz"
    if [ ! -f "$IMAGE" ]; then exit 1; fi

    echo -e "${yellow}>> Packaging...${nocol}"
    [ ! -d "$ANYKERNEL3_DIR" ] && git clone --depth=1 https://github.com/neel0210/AnyKernel3.git -b A22 "$ANYKERNEL3_DIR"
    
    cp "$IMAGE" "$ANYKERNEL3_DIR/"
    cd "$ANYKERNEL3_DIR" || exit
    ZIP_NAME="ARISE-$(git rev-parse --short HEAD)-$DEVICE-$DATE.zip"
    zip -r9 "../$ZIP_NAME" * -x .git README.md >> /dev/null
    cd ..
    FINAL_ZIP="$ZIP_NAME"
}

# --- Run ---
build_kernel
package_kernel
