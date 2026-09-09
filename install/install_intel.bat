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
    echo [1/6] Creating Python virtual environment...
    python -m venv venv
    if %errorlevel% neq 0 goto :VENV_FAIL
) else (
    echo [1/6] Virtual environment already exists, skipping.
)

echo [1/6] Activating virtual environment...
call venv\Scripts\activate.bat
if %errorlevel% neq 0 (
    echo [ERROR] Failed to activate virtual environment.
    goto :FAIL
)

:: 4. Upgrade pip
echo [2/6] Upgrading pip, setuptools, wheel...
python -m pip install --upgrade pip setuptools wheel cmake --quiet

:: 5. Install llama-cpp-python (pre-built, no compiler needed)
echo [3/6] Installing llama-cpp-python (trying Vulkan GPU build first)...
pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/vulkan --only-binary :all: --prefer-binary --quiet
if %errorlevel% neq 0 (
    echo [INFO] Vulkan build not found, falling back to CPU build...
    pip install llama-cpp-python --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu --only-binary :all: --prefer-binary --quiet
)
if %errorlevel% neq 0 (
    echo [ERROR] Could not install llama-cpp-python.
    echo Ensure you are using Python 3.10 or 3.11.
    goto :FAIL
)
echo [OK] llama-cpp-python installed.

:: 6. Install remaining requirements
echo [4/6] Installing remaining requirements (requirements-intel.txt)...
pip install -r requirements-intel.txt --prefer-binary --ignore-installed llama-cpp-python --quiet
if %errorlevel% neq 0 goto :PIP_FAIL

:: 7. Create directories
echo [5/6] Creating required directories...
mkdir index_store 2>nul
mkdir cache      2>nul
mkdir logs       2>nul
mkdir models     2>nul

if not exist "index_store\chunks.json" echo [] > "index_store\chunks.json"

:: 8. Download models
echo [6/6] Downloading models (MiniLM, BGE reranker, Qwen2.5-3B GGUF)...
python download_models.py
if %errorlevel% neq 0 (
    echo [ERROR] Model download failed.
    goto :FAIL
)

:: 9. Post-install check
echo.
echo [INFO] Running post-install check...
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
echo [ERROR] pip install failed.
goto :FAIL
:CHECKS_FAIL
echo [ERROR] Post-install check failed.
goto :FAIL
:FAIL
echo.
echo ========================================================
echo   INSTALLATION FAILED
echo ========================================================
echo Please check the error messages above.
pause
exit /b 1
