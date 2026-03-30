#!/usr/bin/env bash

# SPDX-License-Identifier: MIT
#
# Copyright (C) 2026 rufnx <https://github.com/rufnx>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

set -e

# ==========================================================
#  Main Kernel Build Script
# ==========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==========================================================
#  Configuration (edit here)
# ==========================================================

# Device
DEVICE="a22x"
DEFCONFIG="a22x_defconfig"
ARCH="arm64"

# Paths
SRC="$SCRIPT_DIR"
OUT_DIR="$SCRIPT_DIR/out"
OUTPUT_DIR="$SCRIPT_DIR/output"
LOG_FILE="$OUTPUT_DIR/build.log"

# Toolchain
CLANG_DIR="$SCRIPT_DIR/clang"
CLANG_URL="https://github.com/greenforce-project/greenforce_clang/releases/download/20260321/gf-clang-23.0.0-20260321.tar.gz"

# AnyKernel3
ANYKERNEL_DIR="$SCRIPT_DIR/AnyKernel3"
ANYKERNEL_URL="https://github.com/rufnx/AnyKernel3"
ANYKERNEL_BRANCH="a22x"

# Build identity
KBUILD_BUILD_USER="naifi"
KBUILD_BUILD_HOST="$(hostname)"
export KBUILD_BUILD_USER KBUILD_BUILD_HOST

# Timezone
export TZ="Asia/Jakarta"

# Telegram
# BOT_TOKEN=""
# CHAT_ID="-1002643673545"

# ==========================================================
#  Colors & Styling
# ==========================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ==========================================================
#  Logging Functions
# ==========================================================
log_info() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${WHITE}[INFO]${NC}    $1" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${GREEN}[OK]${NC}      $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}[WARN]${NC}    $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${RED}[ERROR]${NC}   $1" | tee -a "$LOG_FILE"
}

log_progress() {
    echo -e "${CYAN}[$(date '+%H:%M:%S')]${NC} ${PURPLE}[....]${NC}    $1" | tee -a "$LOG_FILE"
}

# ==========================================================
#  Banner
# ==========================================================
print_banner() {
    echo -e "${CYAN}"
    cat << "EOF"
╔══════════════════════════════════════════════╗
║                                              ║
║           KERNEL BUILD SAMSUNG               ║
║                                              ║
╚══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    log_info "Device:  ${YELLOW}${DEVICE}${NC}"
    log_info "Config:  ${YELLOW}${DEFCONFIG}${NC}"
    log_info "Builder: ${YELLOW}${KBUILD_BUILD_USER}@${KBUILD_BUILD_HOST}${NC}"
    echo ""
}

# ==========================================================
#  Progress Spinner
# ==========================================================
spinner() {
    local pid=$1
    local message=$2
    local spin='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 10 ))
        echo -ne "\r${CYAN}[$(date '+%H:%M:%S')]${NC} ${YELLOW}${spin:$i:1}${NC}  $message"
        sleep 0.1
    done
    echo -ne "\r"
}

# ==========================================================
#  Telegram Functions
# ==========================================================
send_to_telegram() {
    local file="$1"
    local caption="$2"

    if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        log_warning "Telegram credentials not set. Skipping upload."
        return
    fi

    log_progress "Uploading to Telegram..."

    local response
    response=$(curl -s \
        -F document=@"$file" \
        -F chat_id="$CHAT_ID" \
        -F parse_mode="Markdown" \
        -F caption="$caption" \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument")

    if echo "$response" | grep -q '"ok":true'; then
        log_success "Upload successful!"
    else
        log_error "Upload failed. Response logged."
        echo "$response" >> "$LOG_FILE"
    fi
}

# ==========================================================
#  Error Handler
# ==========================================================
error_exit() {
    local message="$1"
    log_error "$message"

    if [ -f "$LOG_FILE" ]; then
        local caption="**Kernel Build Failed!**

\`\`\`
Error: $message
Device: $DEVICE
Time: $(date '+%d-%m-%Y %H:%M')
\`\`\`"
        send_to_telegram "$LOG_FILE" "$caption"
    fi

    echo -e "${RED}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}║              BUILD FAILED                    ║${NC}"
    echo -e "${RED}║                                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════╝${NC}"
    exit 1
}

# ==========================================================
#  Build Timer
# ==========================================================
start_timer() {
    BUILD_START=$(date +%s)
    export BUILD_START
}

end_timer() {
    local end_time elapsed minutes seconds
    end_time=$(date +%s)
    elapsed=$((end_time - BUILD_START))
    minutes=$((elapsed / 60))
    seconds=$((elapsed % 60))
    log_info "Build time: ${YELLOW}${minutes}m ${seconds}s${NC}"
}

# ==========================================================
#  Dependency Check
# ==========================================================
verify_dependencies() {
    log_info "Verifying system dependencies..."
    local deps_ok=true

    for cmd in git curl wget zip make tar; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Missing required command: $cmd"
            deps_ok=false
        fi
    done

    [ "$deps_ok" = false ] && error_exit "Missing required dependencies"
    log_success "All system dependencies verified"
}

# ==========================================================
#  Clang Setup (download & extract tar.gz)
# ==========================================================
check_clang() {
    if [ -d "$CLANG_DIR" ] && [ -f "$CLANG_DIR/bin/clang" ]; then
        log_success "Clang toolchain found ($(${CLANG_DIR}/bin/clang --version 2>/dev/null | head -1 || echo 'unknown version'))"
        return 0
    fi

    log_progress "Clang not found. Downloading AOSP Clang r596125..."
    mkdir -p "$CLANG_DIR"

    local tarball="$SCRIPT_DIR/clang.tar.gz"

    # wget untuk nunjukin speed & progress download
    if ! wget --show-progress -q "$CLANG_URL" -O "$tarball" 2>&1 | tee -a "$LOG_FILE"; then
        rm -f "$tarball"
        error_exit "Failed to download Clang tarball"
    fi

    if [ ! -f "$tarball" ] || [ ! -s "$tarball" ]; then
        rm -f "$tarball"
        error_exit "Clang tarball kosong atau tidak ditemukan"
    fi

    log_progress "Extracting Clang..."
    # AOSP clang tar.gz langsung berisi bin/ lib/ dll tanpa subdirektori wrapper
    tar -xzf "$tarball" -C "$CLANG_DIR" >> "$LOG_FILE" 2>&1 &
    spinner $! "Extracting Clang..."
    wait $!

    rm -f "$tarball"

    if [ -f "$CLANG_DIR/bin/clang" ]; then
        log_success "Clang extracted successfully"
    else
        error_exit "Clang extraction failed — bin/clang not found"
    fi
}

# ==========================================================
#  AnyKernel3 Setup
# ==========================================================
check_anykernel() {
    if [ -d "$ANYKERNEL_DIR" ]; then
        log_success "AnyKernel3 already exists"
        return 0
    fi

    log_progress "Cloning AnyKernel3..."
    git clone --depth=1 "$ANYKERNEL_URL" -b "$ANYKERNEL_BRANCH" "$ANYKERNEL_DIR" >> "$LOG_FILE" 2>&1 &
    spinner $! "Cloning AnyKernel3..."
    wait $!

    if [ -d "$ANYKERNEL_DIR" ]; then
        log_success "AnyKernel3 cloned successfully"
    else
        error_exit "Failed to clone AnyKernel3"
    fi
}

# ==========================================================
#  Setup All Dependencies
# ==========================================================
setup_dependencies() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build dependencies..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    verify_dependencies
    check_clang
    check_anykernel

    echo ""
    log_success "All dependencies ready!"
    echo ""
}

# ==========================================================
#  Setup Build Environment
# ==========================================================
setup_environment() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Setting up build environment..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    mkdir -p "$OUT_DIR" "$OUTPUT_DIR"

    # Detect arm32 and compat toolchains from clang bundle
    local gcc_arm32 gcc_arm64
    gcc_arm32=$(find "$CLANG_DIR" -name "arm-linux-gnueabi-gcc" 2>/dev/null | head -1)
    gcc_arm64=$(find "$CLANG_DIR" -name "aarch64-linux-gnu-gcc" 2>/dev/null | head -1)

    if [ -n "$gcc_arm32" ]; then
        CROSS_COMPILE_COMPAT="$(dirname "$gcc_arm32")/arm-linux-gnueabi-"
        log_info "arm32 (compat): ${YELLOW}${CROSS_COMPILE_COMPAT}${NC}"
    else
        # Fallback to system
        CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
        log_warning "arm32 toolchain not found in bundle, falling back to system"
    fi

    if [ -n "$gcc_arm64" ]; then
        CROSS_COMPILE_PATH="$(dirname "$gcc_arm64")/aarch64-linux-gnu-"
    else
        CROSS_COMPILE_PATH="aarch64-linux-gnu-"
        log_warning "aarch64 toolchain not found in bundle, falling back to system"
    fi

    export CROSS_COMPILE_COMPAT CROSS_COMPILE_PATH

    log_info "Architecture: ${YELLOW}${ARCH}${NC}"
    log_info "Compiler:     ${YELLOW}Clang ${LLVM} + LLVM tools${NC}"
    log_info "Threads:      ${YELLOW}$(nproc)${NC}"

    echo ""
    log_success "Environment ready!"
    echo ""
}

# ==========================================================
#  Build Kernel
# ==========================================================
build_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Starting kernel compilation..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    start_timer

    # Common make args
    local PATH_ORIG="$PATH"
    export PATH="$CLANG_DIR/bin:$PATH"

    local MAKE_ARGS=(
        -C "$SRC"
        O="$OUT_DIR"
        ARCH="$ARCH"
        LLVM=1
        LLVM_IAS=1
        CLANG_TRIPLE="aarch64-linux-gnu-"
        CROSS_COMPILE="$CROSS_COMPILE_PATH"
        CROSS_COMPILE_COMPAT="$CROSS_COMPILE_COMPAT"
    )

    # Generate defconfig
    log_progress "Generating defconfig..."
    if make "${MAKE_ARGS[@]}" "$DEFCONFIG" >> "$LOG_FILE" 2>&1; then
        log_success "Defconfig generated"
    else
        export PATH="$PATH_ORIG"
        error_exit "Defconfig generation failed"
    fi

    echo ""
    log_progress "Compiling kernel with $(nproc) threads..."
    echo ""

    # Compile kernel
    if make "${MAKE_ARGS[@]}" -j"$(nproc)" 2>&1 | tee -a "$LOG_FILE"; then
        echo ""
        log_success "Kernel compilation completed!"
    else
        export PATH="$PATH_ORIG"
        error_exit "Kernel compilation failed"
    fi

    export PATH="$PATH_ORIG"

    # Verify kernel image
    local image1="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    local image2="$OUT_DIR/arch/arm64/boot/Image.gz"
    local image3="$OUT_DIR/arch/arm64/boot/Image"

    if [ ! -f "$image1" ] && [ ! -f "$image2" ] && [ ! -f "$image3" ]; then
        error_exit "Kernel image not found after build"
    fi

    end_timer
    echo ""
}

# ==========================================================
#  Package Kernel
# ==========================================================
package_kernel() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    log_info "Creating flashable package..."
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"

    check_anykernel

    # Clean old kernel images from AnyKernel dir
    log_progress "Cleaning AnyKernel directory..."
    rm -f "$ANYKERNEL_DIR"/Image* "$ANYKERNEL_DIR"/*.gz "$ANYKERNEL_DIR"/*.dtb

    # Determine kernel image (priority: Image.gz-dtb > Image.gz > Image)
    local kernel_image=""
    if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
        kernel_image="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
        log_info "Using: ${YELLOW}Image.gz-dtb${NC}"
    elif [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
        kernel_image="$OUT_DIR/arch/arm64/boot/Image.gz"
        log_info "Using: ${YELLOW}Image.gz${NC}"
    else
        kernel_image="$OUT_DIR/arch/arm64/boot/Image"
        log_info "Using: ${YELLOW}Image${NC}"
    fi

    # Copy kernel image
    log_progress "Copying kernel image..."
    if cp "$kernel_image" "$ANYKERNEL_DIR/"; then
        log_success "Kernel image copied"
    else
        error_exit "Failed to copy kernel image"
    fi

    # Also copy dtbo.img if exists
    if [ -f "$OUT_DIR/arch/arm64/boot/dtbo.img" ]; then
        cp "$OUT_DIR/arch/arm64/boot/dtbo.img" "$ANYKERNEL_DIR/"
        log_info "dtbo.img included"
    fi

    # Create zip
    local zipname="${DEVICE}-$(date +%Y%m%d-%H%M).zip"
    log_progress "Creating ZIP package..."

    (cd "$ANYKERNEL_DIR" && zip -r9 "$OUTPUT_DIR/$zipname" . -x ".git/*" -x "*.md" > /dev/null 2>&1)

    if [ -f "$OUTPUT_DIR/$zipname" ]; then
        log_success "Package created: ${YELLOW}$zipname${NC}"
    else
        error_exit "Failed to create ZIP package"
    fi

    # Get kernel version
    local kernel_ver
    kernel_ver=$(strings "$OUT_DIR/arch/arm64/boot/Image" 2>/dev/null | grep "Linux version")
    local date_now
    date_now=$(date +"%d-%m-%Y %H:%M")

    # Telegram caption
    local caption="**${DEVICE} Kernel Build**

\`\`\`
Date     : ${date_now}
Version  : ${kernel_ver}
\`\`\`

**Flash via Recovery Only**"

    echo ""
    send_to_telegram "$OUTPUT_DIR/$zipname" "$caption"
    echo ""
    log_success "Output: ${YELLOW}output/$zipname${NC}"
    echo ""
}

# ==========================================================
#  Main Build Process
# ==========================================================
main() {
    # Ensure output dir exists for log
    if [ -d "$OUT_DIR" ]; then
        rm -rf $OUT_DIR
        rm -f "$LOG_FILE"
        mkdir -p "$OUTPUT_DIR"
    fi

    print_banner

    log_info "Build started at $(date '+%d-%m-%Y %H:%M:%S')"
    echo ""

    setup_dependencies
    setup_environment
    build_kernel
    package_kernel

    echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}║           BUILD COMPLETED                    ║${NC}"
    echo -e "${GREEN}║                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"

    log_success "Build finished successfully!"
    log_info "Check output/ directory for flashable ZIP"
    echo ""
}

# ==========================================================
#  Run
# ==========================================================
main "$@"
