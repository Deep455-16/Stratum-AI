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

:: Model paths — override via environment variables if models live elsewhere.
:: SNAPDRAGON_MODEL_PATH : Qwen3-4B ONNX model directory
:: EMBED_MODEL_PATH      : Sentence embedding model directory
:: RERANKER_MODEL_PATH   : BGE reranker model directory
if "%SNAPDRAGON_MODEL_PATH%"=="" set SNAPDRAGON_MODEL_PATH=models\Qwen3-4B-onnx
if "%EMBED_MODEL_PATH%"==""      set EMBED_MODEL_PATH=models\MiniLM-L6-v2
if "%RERANKER_MODEL_PATH%"==""   set RERANKER_MODEL_PATH=models\bge-reranker-base

echo   LLM_BACKEND           = %LLM_BACKEND%
echo   SNAPDRAGON_MODEL_PATH = %SNAPDRAGON_MODEL_PATH%
echo   EMBED_MODEL_PATH      = %EMBED_MODEL_PATH%
echo   RERANKER_MODEL_PATH   = %RERANKER_MODEL_PATH%
echo   QNN_BACKEND_TYPE      = %QNN_BACKEND_TYPE%
echo.

:: Check venv
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found.
    echo Please run install\install_snapdragon.bat first.
    goto :FAIL
)
call venv\Scripts\activate.bat

:: Quick dependency check — catch missing packages before launching
echo [INFO] Checking core dependencies...
python -c "import faiss, rank_bm25, fastapi, transformers, yaml, psutil, huggingface_hub" 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] One or more required packages are missing.
    echo Please re-run install\install_snapdragon.bat to repair the installation.
    goto :FAIL
)
echo [OK] Core dependencies OK.

:: Check onnxruntime-qnn
echo [INFO] Checking QNNExecutionProvider...
python -c "import onnxruntime as ort; assert 'QNNExecutionProvider' in ort.get_all_providers(), 'QNNExecutionProvider not found'" 2>&1
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
echo.

:: Check ONNX model
if not exist "%SNAPDRAGON_MODEL_PATH%\" (
    echo [ERROR] Snapdragon model not found at: %SNAPDRAGON_MODEL_PATH%
    echo Run install\install_snapdragon.bat to download it.
    goto :FAIL
)
echo [OK] ONNX model found.

:: Check embedding model (uses EMBED_MODEL_PATH env var set above)
if not exist "%EMBED_MODEL_PATH%\model.safetensors" (
    if not exist "%EMBED_MODEL_PATH%\pytorch_model.bin" (
        echo [ERROR] Embedding model not found at: %EMBED_MODEL_PATH%
        echo         Run install\install_snapdragon.bat or set EMBED_MODEL_PATH to the correct path.
        goto :FAIL
    )
)
echo [OK] Embedding model found.

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
echo [INFO] Starting server... (Press Ctrl+C to stop)
echo [INFO] Browser will open automatically in 3 seconds.
echo.

:: Launch browser after a short delay (runs in background, doesn't block server)
start "" cmd /c "timeout /t 3 /nobreak >nul && start http://127.0.0.1:8000"

python -m uvicorn server:app --host 127.0.0.1 --port 8000 --workers 1

echo.
echo [INFO] Server stopped.
pause
exit /b 0

:INGEST_FAIL
echo [ERROR] Ingestion failed. Check output above.
goto :FAIL
:FAIL
echo.
echo [ERROR] Startup failed. Check messages above.
pause
exit /b 1
