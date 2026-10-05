@echo off
setlocal enabledelayedexpansion
title Stratum AI - Snapdragon Installation

:: Always run relative to project root (one level up from install/)
cd /d "%~dp0.."

echo ========================================================
echo   Stratum AI - Snapdragon / Qualcomm QNN Installation
echo ========================================================
echo.
echo   REQUIREMENTS:
echo     - Windows ARM64 (Snapdragon X Elite / X2 Elite)
echo     - Python 3.11 recommended
echo     - Internet connection (one-time model download)
echo.
echo   LLM backend: ONNX Runtime + QNNExecutionProvider + Qwen3-4B
echo.

:: 0. Warn if not ARM64
for /f "tokens=2 delims==" %%A in ('wmic os get OSArchitecture /value 2^>nul') do set OS_ARCH=%%A
echo  Detected OS architecture: %OS_ARCH%
echo %OS_ARCH% | findstr /i "ARM" >nul
if %errorlevel% neq 0 (
    echo.
    echo  [WARNING] This machine does not appear to be Windows ARM64.
    echo  onnxruntime-qnn only works on Snapdragon hardware.
    echo  Press any key to continue anyway, or close this window to abort.
    echo.
    pause
)

:: 1. Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python not found in PATH.
    goto :FAIL
)

:: 2. Create / activate venv
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

:: 3. Upgrade pip / build tools
echo.
echo [2/7] Upgrading pip, setuptools, wheel...
python -m pip install --upgrade pip setuptools wheel
if %errorlevel% neq 0 goto :PIP_FAIL

:: 4a. Install torch separately FIRST — it is large (~2 GB) and pip may appear
::     frozen when downloading it silently. Progress is now visible.
echo.
echo [3/7] Installing PyTorch (this may take several minutes - progress shown)...
pip install torch --prefer-binary
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] torch installed.

:: 4b. Install transformers + huggingface_hub
echo.
echo [3/7] Installing transformers and huggingface_hub...
pip install transformers huggingface_hub --prefer-binary
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] transformers + huggingface_hub installed.

:: 4c. Install all remaining common dependencies
echo.
echo [3/7] Installing common dependencies (requirements-intel.txt)...
pip install -r requirements-intel.txt --prefer-binary
if %errorlevel% neq 0 goto :PIP_FAIL
echo [OK] Common dependencies installed.

:: 5. Install Snapdragon-specific dependencies (onnxruntime-qnn, genai)
echo.
echo [4/7] Installing Snapdragon deps (onnxruntime-qnn, onnxruntime-genai)...
echo       Note: These are ARM64-only packages. Progress shown below.
pip install -r requirements-snapdragon.txt --prefer-binary
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install Snapdragon dependencies.
    echo Make sure you are on a Windows ARM64 machine.
    goto :FAIL
)
echo [OK] onnxruntime-qnn and onnxruntime-genai installed.

:: 6. Create required directories
echo.
echo [5/7] Creating required directories...
mkdir index_store 2>nul
mkdir cache       2>nul
mkdir logs        2>nul
mkdir models      2>nul
if not exist "index_store\chunks.json" echo [] > "index_store\chunks.json"

:: 7. Download embedding + reranker models
echo.
echo [6/7] Downloading embedding + reranker models...
python download_models.py
if %errorlevel% neq 0 (
    echo [ERROR] Model download failed.
    goto :FAIL
)

:: 8. Download Qwen3-4B ONNX model
echo.
echo [7/7] Downloading Qwen3-4B ONNX model from Hugging Face...
echo       (One-time download: ~4-8 GB depending on quantization)
echo       Destination: models\Qwen3-4B-onnx
echo.

if exist "models\Qwen3-4B-onnx\*.onnx" (
    echo [INFO] Qwen3-4B ONNX model already exists, skipping download.
) else (
    huggingface-cli download qualcomm/Qwen3-4B --local-dir models\Qwen3-4B-onnx
    if %errorlevel% neq 0 (
        echo.
        echo [WARNING] huggingface-cli download failed.
        echo You can manually download from:
        echo   https://huggingface.co/qualcomm/Qwen3-4B
        echo   or: https://aihub.qualcomm.com/compute/models/qwen3-4b
        echo Place the files in:  models\Qwen3-4B-onnx\
        echo.
    ) else (
        echo [OK] Qwen3-4B ONNX model downloaded.
    )
)

:: 9. Post-install check
echo.
echo [INFO] Running post-install check...
python -c "import faiss, rank_bm25, fastapi, transformers, yaml, psutil; print('[OK] Core libraries imported.')"
if %errorlevel% neq 0 goto :CHECKS_FAIL

:: 10. Verify QNN availability
echo.
echo [INFO] Verifying QNNExecutionProvider...
python -c "import onnxruntime as ort; avail = 'QNNExecutionProvider' in ort.get_all_providers(); print('[OK] QNNExecutionProvider AVAILABLE' if avail else '[WARNING] QNNExecutionProvider NOT found - check hardware/install')"

echo.
echo ========================================================
echo   SNAPDRAGON INSTALLATION COMPLETE
echo ========================================================
echo.
echo   Next steps:
echo     1. python ingest.py               (index your runbooks)
echo     2. launchers\start_snapdragon.bat (start on NPU)
echo.
echo   To verify NPU is active after starting:
echo     curl http://127.0.0.1:8000/api/llm/health
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
