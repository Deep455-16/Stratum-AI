@echo off
setlocal enabledelayedexpansion
title Stratum AI - Snapdragon Launcher

:: Always run relative to project root (one level up from launchers/)
cd /d "%~dp0.."

echo ========================================================
echo   Stratum AI - Snapdragon NPU Mode
echo   LLM: Qwen3-4B ONNX via QNNExecutionProvider
echo ========================================================
echo.

:: Force Snapdragon backend
set LLM_BACKEND=snapdragon
set QNN_ENABLED=1
set QNN_BACKEND_TYPE=npu

:: Allow override of model path
if "%SNAPDRAGON_MODEL_PATH%"=="" set SNAPDRAGON_MODEL_PATH=models\Qwen3-4B-onnx

echo   LLM_BACKEND           = %LLM_BACKEND%
echo   SNAPDRAGON_MODEL_PATH = %SNAPDRAGON_MODEL_PATH%
echo   QNN_BACKEND_TYPE      = %QNN_BACKEND_TYPE%
echo.

:: Check venv
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found.
    echo Please run install\install_snapdragon.bat first.
    goto :FAIL
)
call venv\Scripts\activate.bat

:: Check onnxruntime-qnn
python -c "import onnxruntime as ort; assert 'QNNExecutionProvider' in ort.get_all_providers()" >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] QNNExecutionProvider not found.
    echo.
    echo   This launcher requires:
    echo     - Windows ARM64 with Qualcomm Snapdragon SoC
    echo     - onnxruntime-qnn installed
    echo.
    echo   Run install\install_snapdragon.bat to set up.
    goto :FAIL
)
echo [OK] QNNExecutionProvider confirmed.

:: Check ONNX model
if not exist "%SNAPDRAGON_MODEL_PATH%\" (
    echo [ERROR] Snapdragon model not found at: %SNAPDRAGON_MODEL_PATH%
    echo Run install\install_snapdragon.bat to download it.
    goto :FAIL
)
echo [OK] ONNX model found.

:: Check embedding model
if not exist "models\MiniLM-L6-v2\model.safetensors" (
    if not exist "models\MiniLM-L6-v2\pytorch_model.bin" (
        echo [ERROR] Embedding model missing. Run install\install_snapdragon.bat.
        goto :FAIL
    )
)

:: Auto-ingest if index is missing
if not exist "index_store\faiss.index" (
    echo [INFO] Index not found. Running ingest.py first...
    python ingest.py
    if %errorlevel% neq 0 goto :INGEST_FAIL
)

echo.
echo  +---------------------------------------+
echo  ^|   STRATUM AI - SNAPDRAGON MODE        ^|
echo  ^|   Backend : http://127.0.0.1:8000     ^|
echo  ^|   LLM     : Qwen3-4B (ONNX)          ^|
echo  ^|   Runtime : ONNX Runtime + QNN        ^|
echo  ^|   Device  : Snapdragon NPU            ^|
echo  +---------------------------------------+
echo.
echo [INFO] Starting server...
echo.

python -m uvicorn server:app --host 127.0.0.1 --port 8000 --workers 1

echo.
echo [INFO] Server stopped.
pause
exit /b 0

:INGEST_FAIL
echo [ERROR] Ingestion failed.
goto :FAIL
:FAIL
echo.
echo [ERROR] Startup failed. Check messages above.
pause
exit /b 1
