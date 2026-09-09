@echo off
REM ============================================================
REM  install_snapdragon.bat
REM  Stratum AI — Snapdragon / Qualcomm QNN installer
REM ============================================================
REM  REQUIREMENTS:
REM    - Windows ARM64 machine (Snapdragon X Elite / X2 Elite)
REM    - Python 3.11 or 3.12 installed and on PATH
REM    - Internet connection (first run only — to download model)
REM
REM  After this script completes:
REM    1. Run:  python ingest.py
REM    2. Run:  START_APP_SNAPDRAGON.bat
REM ============================================================

echo.
echo  ============================================================
echo   STRATUM AI — Snapdragon Backend Installer
echo  ============================================================
echo.

REM ── Step 0: Sanity check — warn if not ARM64 ─────────────────
for /f "tokens=*" %%A in ('wmic os get OSArchitecture /value 2^>nul') do set OS_ARCH=%%A
echo  Detected: %OS_ARCH%
echo %OS_ARCH% | findstr /i "ARM" >nul
if errorlevel 1 (
    echo.
    echo  [WARNING] This machine does not appear to be ARM64.
    echo  onnxruntime-qnn requires Windows ARM64 + Snapdragon hardware.
    echo  Installation will continue but QNN may not work.
    echo.
    pause
)

REM ── Step 1: Create / activate virtual environment ────────────
if not exist venv (
    echo  [1/5] Creating virtual environment ...
    python -m venv venv
) else (
    echo  [1/5] Virtual environment already exists, skipping creation.
)

call venv\Scripts\activate.bat
echo  [1/5] Virtual environment activated.
echo.

REM ── Step 2: Upgrade pip ───────────────────────────────────────
echo  [2/5] Upgrading pip ...
python -m pip install --upgrade pip --quiet
echo  [2/5] Done.
echo.

REM ── Step 3: Install common dependencies ──────────────────────
echo  [3/5] Installing common dependencies (requirements-intel.txt) ...
pip install -r requirements-intel.txt --quiet
if errorlevel 1 (
    echo  [ERROR] Failed to install common dependencies.
    pause
    exit /b 1
)
echo  [3/5] Common dependencies installed.
echo.

REM ── Step 4: Install Snapdragon-specific dependencies ─────────
echo  [4/5] Installing Snapdragon dependencies (onnxruntime-qnn, onnxruntime-genai) ...
pip install -r requirements-snapdragon.txt --quiet
if errorlevel 1 (
    echo  [ERROR] Failed to install Snapdragon dependencies.
    echo  Make sure you are on a Windows ARM64 machine.
    pause
    exit /b 1
)
echo  [4/5] Snapdragon dependencies installed.
echo.

REM ── Step 5: Download Qwen3-4B ONNX model ─────────────────────
echo  [5/5] Downloading Qwen3-4B ONNX model from Hugging Face ...
echo        (This is a one-time download; ~4-8 GB depending on quantization)
echo        Model will be saved to:  models\Qwen3-4B-onnx
echo.

if not exist models mkdir models

REM Check if model already downloaded
if exist models\Qwen3-4B-onnx\*.onnx (
    echo  [5/5] Model already exists at models\Qwen3-4B-onnx — skipping download.
) else (
    huggingface-cli download qualcomm/Qwen3-4B --local-dir models\Qwen3-4B-onnx
    if errorlevel 1 (
        echo.
        echo  [WARNING] huggingface-cli download failed.
        echo  You can manually download the model from:
        echo    https://huggingface.co/qualcomm/Qwen3-4B
        echo    or: https://aihub.qualcomm.com/compute/models/qwen3-4b
        echo  and place it in:  models\Qwen3-4B-onnx\
        echo.
    ) else (
        echo  [5/5] Model downloaded successfully.
    )
)

echo.
echo  ============================================================
echo   Installation complete!
echo  ============================================================
echo.
echo  Next steps:
echo    1. python ingest.py          (index your runbooks)
echo    2. START_APP_SNAPDRAGON.bat  (start Stratum AI on NPU)
echo.
echo  To verify QNN is available after starting:
echo    curl http://127.0.0.1:8000/api/hardware
echo    curl http://127.0.0.1:8000/api/llm/health
echo.
pause
