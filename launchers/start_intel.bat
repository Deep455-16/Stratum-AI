@echo off
setlocal enabledelayedexpansion
title Stratum AI - Intel Launcher

:: Always run relative to project root (one level up from launchers/)
cd /d "%~dp0.."

echo ========================================================
echo   Stratum AI - Intel / CPU Mode
echo   LLM: Qwen2.5-3B GGUF via llama.cpp
echo ========================================================
echo.

set LLM_BACKEND=llama

:: Check venv
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found.
    echo Please run install\install_intel.bat first.
    goto :FAIL
)
call venv\Scripts\activate.bat

:: Check embedding model
if not exist "models\MiniLM-L6-v2\model.safetensors" (
    if not exist "models\MiniLM-L6-v2\pytorch_model.bin" (
        echo [ERROR] Embedding model missing. Run install\install_intel.bat.
        goto :FAIL
    )
)

:: Check LLM model
if not exist "models\Qwen2.5-3B-Instruct-Q3_K_M.gguf" (
    echo [ERROR] LLM model missing. Run install\install_intel.bat.
    goto :FAIL
)

:: Auto-ingest if index is missing
if not exist "index_store\faiss.index" (
    echo [INFO] Index not found. Running ingest.py first...
    python ingest.py
    if %errorlevel% neq 0 goto :INGEST_FAIL
)

:: Warmup
echo [INFO] Warming up embedding model...
python -c "from pipeline.embedder import get_embedder; get_embedder().encode(['warmup'])" >nul 2>&1

echo.
echo  +---------------------------------------+
echo  ^|   STRATUM AI - INTEL MODE             ^|
echo  ^|   Backend : http://127.0.0.1:8000     ^|
echo  ^|   LLM     : Qwen2.5-3B (llama.cpp)   ^|
echo  ^|   Device  : CPU                       ^|
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
