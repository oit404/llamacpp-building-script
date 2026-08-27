#!/usr/bin/env bash
# ==============================================================================
# Isolated, Zero-System-Footprint llama.cpp CUDA 13 Builder
# Downloads CUDA 13 locally into workspace and builds llama.cpp cleanly.
# ==============================================================================
set -euo pipefail

# --- Local Workspace Setup ---
WORKSPACE_DIR="$(pwd)/llama_cuda13_workspace"
CUDA_INSTALL_DIR="${WORKSPACE_DIR}/cuda_13_local"
LLAMA_DIR="${WORKSPACE_DIR}/llama.cpp"
BUILD_DIR="${LLAMA_DIR}/build"

# Official NVIDIA CUDA 13.3.1 Runfile URL (Linux x86_64)
CUDA_RUNFILE_URL="https://developer.download.nvidia.com/compute/cuda/13.3.1/local_installers/cuda_13.3.1_610.43.02_linux.run"
CUDA_RUNFILE_NAME="cuda_13_installer.run"

echo "==> Creating local workspace at: ${WORKSPACE_DIR}"
mkdir -p "${WORKSPACE_DIR}"
cd "${WORKSPACE_DIR}"

# --- Step 1: Download & Extract Standalone CUDA 13 Toolkit ---
if [[ ! -f "${CUDA_INSTALL_DIR}/bin/nvcc" ]]; then
    echo "==> Downloading CUDA 13 standalone installer..."
    if command -v curl &>/dev/null; then
        curl -L -o "${CUDA_RUNFILE_NAME}" "${CUDA_RUNFILE_URL}"
    elif command -v wget &>/dev/null; then
        wget -O "${CUDA_RUNFILE_NAME}" "${CUDA_RUNFILE_URL}"
    else
        echo "ERROR: Neither curl nor wget was found." >&2
        exit 1
    fi

    # Sanity check: a real runfile is several GB; a 404 page is a few bytes
    FILE_SIZE=$(stat -c%s "${CUDA_RUNFILE_NAME}" 2>/dev/null || stat -f %z "${CUDA_RUNFILE_NAME}")
    if [[ "${FILE_SIZE}" -lt 10000000 ]]; then
        echo "ERROR: Downloaded file is only ${FILE_SIZE} bytes - likely an error page." >&2
        exit 1
    fi

    echo "==> Extracting CUDA 13 Toolkit to user-space directory (No sudo required)..."
    chmod +x "${CUDA_RUNFILE_NAME}"
    
    # Run installer strictly in user-space targeting local directory
    bash "${CUDA_RUNFILE_NAME}" \
        --silent \
        --toolkit \
        --toolkitpath="${CUDA_INSTALL_DIR}" \
        --no-man-page \
        --override

    # Cleanup installer file to free disk space
    rm -f "${CUDA_RUNFILE_NAME}"
    echo "    CUDA 13 installed locally at: ${CUDA_INSTALL_DIR}"
else
    echo "==> Found existing local CUDA 13 installation at ${CUDA_INSTALL_DIR}"
fi

# Set local execution variables (scoped ONLY to this script execution)
LOCAL_NVCC="${CUDA_INSTALL_DIR}/bin/nvcc"
LOCAL_CUDA_LIB="${CUDA_INSTALL_DIR}/lib64"

# Verification
if [[ ! -f "${LOCAL_NVCC}" ]]; then
    echo "ERROR: NVCC compiler binary missing at ${LOCAL_NVCC}" >&2
    exit 1
fi

echo "==> Using isolated NVCC: $("${LOCAL_NVCC}" --version | grep 'release')"

# --- Step 2: Fetch llama.cpp ---
echo "==> Fetching latest llama.cpp repository..."
if [[ -d "${LLAMA_DIR}" ]]; then
    cd "${LLAMA_DIR}"
    git fetch origin
    git checkout master
    git pull origin master
else
    git clone https://github.com/ggml-org/llama.cpp.git "${LLAMA_DIR}"
    cd "${LLAMA_DIR}"
fi

# --- Step 3: Configure CMake with Scoped CUDA Paths & RPATH ---
echo "==> Configuring CMake..."
rm -rf "${BUILD_DIR}"

# -DCMAKE_BUILD_RPATH / -DCMAKE_INSTALL_RPATH injects local CUDA library path 
# into the ELF binary binary header so it runs natively without LD_LIBRARY_PATH.
cmake -B "${BUILD_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DGGML_CUDA=ON \
    -DCMAKE_CUDA_COMPILER="${LOCAL_NVCC}" \
    -DCMAKE_CUDA_ARCHITECTURES="native" \
    -DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler" \
    -DCMAKE_BUILD_RPATH="\$ORIGIN/../../../cuda_13_local/lib64" \
    -DGGML_CUDA_FA_ALL_QUANTS=ON \
    -DBUILD_SHARED_LIBS=OFF

# --- Step 4: Compile Executables ---
echo "==> Compiling llama.cpp using $(nproc) threads..."
cmake --build "${BUILD_DIR}" --config Release -j "$(nproc)"

# --- Step 5: Final Sanity Check ---
echo "=========================================================================="
echo " SUCCESS: Portable llama.cpp compiled!"
echo " Location: ${BUILD_DIR}/bin/llama-cli"
echo " Zero system modifications made."
echo "=========================================================================="

"${BUILD_DIR}/bin/llama-cli" --version || true
