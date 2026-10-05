@echo off
setlocal enabledelayedexpansion
title Stratum AI - Intel Installation

:: Always run relative to project root (one level up from install/)
cd /d "%~dp0.."

echo ========================================================
echo   Stratum AI - Intel / CPU Installation
echo ========================================================
echo.
echo   This installer sets up Stratum AI for Intel/AMD CPUs.
echo   LLM backend: llama.cpp + Qwen2.5-3B GGUF
echo.

:: 1. Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed or not in PATH.
    echo Please install Python 3.10 or 3.11 and check "Add to PATH".
    goto :FAIL
)

:: 2. Check Git (informational only)
git --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [WARNING] Git is not installed. Some pip deps may fail.
)

:: 3. Create / activate venv
if not exist "venv\" (
    echo [1/7] Creating Python virtual environment...
    python -m venv venv
    if %errorlevel% neq 0 goto :VENV_FAIL
) else (
    echo [1/7] Virtual environment already exists, skipping.
)

echo [1/7] Activating virtual environment...
call venv\Scripts\activate.bat
if %errorlevel% neq 0 (
    echo [ERROR] Failed to activate virtual environment.
    goto :FAIL
)

:: 4. Upgrade pip / build tools
echo.
echo [2/7] Upgrading pip, setuptools, wheel...
python -m pip install --upgrade pip setuptools wheel cmake
if %errorlevel% neq 0 goto :PIP_FAIL

:: 5. Install llama-cpp-python (pre-built, no compiler needed)
echo.
echo [3/7] Installing llama-cpp-python (trying Vulkan GPU build first)...
pip install llama-cpp-python ^
    --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/vulkan ^
    --only-binary :all: --prefer-binary
if %errorlevel% neq 0 (
    echo [INFO] Vulkan build not found, falling back to CPU build...
    pip install llama-cpp-python ^
        --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu ^
        --only-binary :all: --prefer-binary
)
if %errorlevel% neq 0 (
    echo [ERROR] Could not install llama-cpp-python.
    echo Ensure you are using Python 3.10 or 3.11.
    goto :FAIL
)
echo [OK] llama-cpp-python installed.

:: 6a. Install torch separately FIRST — it is large (~2 GB) and pip may appear
::     frozen when downloading it silently. Progress is now visible.
echo.
echo [4/7] Installing PyTorch (this may take several minutes - progress shown)...
pip install torch --prefer-binary
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] torch installed.

:: 6b. Install transformers + huggingface_hub
echo.
echo [4/7] Installing transformers and huggingface_hub...
pip install transformers huggingface_hub --prefer-binary
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] transformers + huggingface_hub installed.

:: 6c. Install all remaining requirements (torch + llama-cpp-python already done)
echo.
echo [4/7] Installing remaining requirements (requirements-intel.txt)...
pip install -r requirements-intel.txt ^
    --prefer-binary ^
    --ignore-installed llama-cpp-python
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] All requirements installed.

:: 7. Create directories
echo.
echo [5/7] Creating required directories...
mkdir index_store 2>nul
mkdir cache      2>nul
mkdir logs       2>nul
mkdir models     2>nul

if not exist "index_store\chunks.json" echo [] > "index_store\chunks.json"

:: 8. Download models
echo.
echo [6/7] Downloading models (MiniLM, BGE reranker, Qwen2.5-3B GGUF)...
python download_models.py
if %errorlevel% neq 0 (
    echo [ERROR] Model download failed.
    goto :FAIL
)

:: 9. Post-install check
echo.
echo [7/7] Running post-install check...
python -c "import faiss, rank_bm25, fastapi, transformers, yaml, psutil; print('[OK] Core libraries imported.')"
if %errorlevel% neq 0 goto :CHECKS_FAIL

echo.
echo [INFO] Hardware info:
python check_gpu.py

echo.
echo ========================================================
echo   INTEL INSTALLATION COMPLETE
echo ========================================================
echo.
echo   Next steps:
echo     1. python ingest.py          (index your runbooks)
echo     2. launchers\start_intel.bat (start the app)
echo.
pause
exit /b 0

:VENV_FAIL
echo [ERROR] Failed to create virtual environment.
goto :FAIL
:PIP_FAIL
echo [ERROR] pip install failed. Check the output above for details.
goto :FAIL
:CHECKS_FAIL
echo [ERROR] Post-install check failed. Some packages may not have installed correctly.
goto :FAIL
:FAIL
echo.
echo ========================================================
echo   INSTALLATION FAILED
echo ========================================================
echo Please check the error messages above.
pause
exit /b 1
