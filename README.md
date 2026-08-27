# building-llama

An isolated, zero-system-footprint builder for [llama.cpp](https://github.com/ggml-org/llama.cpp)
with CUDA GPU support. `script.sh` downloads the NVIDIA CUDA 13.3.1 Toolkit into a local
workspace (no `sudo`, no system packages) and compiles llama.cpp against it. The resulting
binaries are self-contained: they carry an `$ORIGIN`-relative RPATH, so the whole workspace
can be moved to another machine without any environment setup.

## Prerequisites

| Requirement | Details |
|---|---|
| OS | Linux x86_64 |
| NVIDIA GPU | Any CUDA-capable GPU, with its driver installed. nvcc detects the local GPU at build time and compiles for it only (`native`), so both are needed now and at run time. |
| NVIDIA driver | Recent enough for CUDA 13.3 (driver **575.x or newer**). No CUDA install needed — the toolkit is bundled in the workspace. |
| C/C++ compiler | GCC (any recent version). GCC 16+ is newer than nvcc officially supports; the script passes `-allow-unsupported-compiler` so it works anyway. |
| Build tools | `cmake` (3.20+), `make`, `git` |
| Download tool | `curl` **or** `wget` |
| Disk | ~15 GB free (~4.1 GB CUDA download, ~7 GB toolkit, ~6 GB llama.cpp + build) |
| Network | `developer.download.nvidia.com` and `github.com` reachable |
| Privileges | None — everything runs in user space, no `sudo` |

## What the script does

```
./script.sh
```

1. **Create workspace** — makes `llama_cuda13_workspace/` in the current directory.
2. **Download & install CUDA 13.3.1** (first run only) — downloads the 4.1 GB runfile
   from NVIDIA into the workspace, then extracts the toolkit into `llama_cuda13_workspace/cuda_13_local/`.
   The installer is deleted afterwards. If `cuda_13_local/bin/nvcc` already exists, this step is skipped.
3. **Fetch llama.cpp** — clones the repository (or pulls the latest `master` if already present).
4. **Configure CMake** — Release build, `GGML_CUDA=ON`, using the local `nvcc`, CUDA
   architecture set to `native`, `$ORIGIN`-relative RPATH, all Flash-Attention quant
   types enabled, static linking.
5. **Build** — compiles everything into `llama_cuda13_workspace/llama.cpp/build/bin/`.
6. **Sanity check** — runs `llama-cli --version`.

Re-running the script refreshes llama.cpp to the latest commit, reconfigures, and rebuilds
(the previous build tree is removed first). The CUDA download is skipped.

## Workspace layout

```
llama_cuda13_workspace/
├── cuda_13_local/                # CUDA 13.3.1 Toolkit (user-space install)
│   ├── bin/nvcc                  # sentinel — script skips re-download while this exists
│   ├── lib64                     # -> targets/x86_64-linux/lib (runtime CUDA libraries)
│   └── targets/x86_64-linux/     # toolkit: include/, lib/, nvvm/
└── llama.cpp/                    # llama.cpp source + build
    ├── build/bin/                # all executables (llama-cli, llama-server, llama-bench, ...)
    └── .git/
```

## Running

```
./llama_cuda13_workspace/llama.cpp/build/bin/llama-cli          # interactive CLI
./llama_cuda13_workspace/llama.cpp/build/bin/llama-server --model <gguf>
./llama_cuda13_workspace/llama.cpp/build/bin/llama-bench        # benchmarking
```

No `LD_LIBRARY_PATH`, `PATH` or other environment setup is required.

## Moving to another PC

Move the entire `llama_cuda13_workspace/` directory. Binaries locate the CUDA libraries
relative to their own path (`$ORIGIN/../../../cuda_13_local/lib64` in the RPATH), so no
paths need adjusting. The destination machine needs:

- an NVIDIA GPU of the **same architecture** (the build targets the local GPU only),
- a CPU with the same instruction set (CPU backend is compiled with `-march=native`),
- an NVIDIA driver new enough for CUDA 13.3 (575.x or newer).

## Notes

- `CMAKE_BUILD_RPATH` uses `$ORIGIN` deliberately. Do not set `CMAKE_SKIP_BUILD_RPATH` or
  `CMAKE_INSTALL_RPATH` on this CMake — with CMake 4.3 they interfere and mangle the rpath.
- `cuda_13_local` is trimmed to the minimum needed for build + run (the nsight profilers
  and unused CUDA libraries are removed); the full toolkit can be re-extracted from the
  NVIDIA runfile if ever needed.
- If you ever delete `cuda_13_local/bin/nvcc`, the script treats the toolkit as missing and
  re-downloads it.
