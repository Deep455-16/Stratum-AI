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
    echo [1/5] Creating Python virtual environment...
    python -m venv venv
    if %errorlevel% neq 0 goto :VENV_FAIL
) else (
    echo [1/5] Virtual environment already exists, skipping.
)

echo [1/5] Activating virtual environment...
call venv\Scripts\activate.bat
if %errorlevel% neq 0 (
    echo [ERROR] Failed to activate virtual environment.
    goto :FAIL
)

:: 3. Upgrade pip
echo [2/5] Upgrading pip...
python -m pip install --upgrade pip --quiet

:: 4. Install common dependencies
echo [3/5] Installing common dependencies (requirements-intel.txt)...
pip install -r requirements-intel.txt --quiet
if %errorlevel% neq 0 goto :PIP_FAIL

:: 5. Install Snapdragon-specific dependencies
echo [4/5] Installing Snapdragon deps (onnxruntime-qnn, onnxruntime-genai)...
pip install -r requirements-snapdragon.txt --quiet
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install Snapdragon dependencies.
    echo Make sure you are on a Windows ARM64 machine.
    goto :FAIL
)
echo [OK] onnxruntime-qnn and onnxruntime-genai installed.

:: 6. Download embedding + reranker models
echo.
echo [5/5] Downloading embedding + reranker models...
python download_models.py
if %errorlevel% neq 0 (
    echo [ERROR] Model download failed.
    goto :FAIL
)

:: 7. Download Qwen3-4B ONNX model
echo.
echo [BONUS] Downloading Qwen3-4B ONNX model from Hugging Face...
echo         (One-time download: ~4-8 GB depending on quantization)
echo         Destination: models\Qwen3-4B-onnx
echo.

mkdir models 2>nul

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

:: 8. Create required directories
mkdir index_store 2>nul
mkdir cache       2>nul
mkdir logs        2>nul
if not exist "index_store\chunks.json" echo [] > "index_store\chunks.json"

:: 9. Verify QNN availability
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
echo [ERROR] pip install failed.
goto :FAIL
:FAIL
echo.
echo ========================================================
echo   INSTALLATION FAILED
echo ========================================================
echo Please check the error messages above.
pause
exit /b 1
