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

:: Point directly to the existing GGUF — no re-download needed.
:: To use a different model file, change this path or set LLM_MODEL_PATH before running.
set LLM_MODEL_PATH=C:\Users\rav62\OneDrive\Desktop\hpe-runbook-main\hpe-runbook-main\models\Qwen2.5-3B-Instruct-Q3_K_M.gguf

:: Embedding / reranker paths — defaults to local models\ directory.
:: Override via env var if they live elsewhere.
if "%EMBED_MODEL_PATH%"==""    set EMBED_MODEL_PATH=models\MiniLM-L6-v2
if "%RERANKER_MODEL_PATH%"=="" set RERANKER_MODEL_PATH=models\bge-reranker-base

echo   LLM_BACKEND        = %LLM_BACKEND%
echo   LLM_MODEL_PATH     = %LLM_MODEL_PATH%
echo   EMBED_MODEL_PATH   = %EMBED_MODEL_PATH%
echo   RERANKER_MODEL_PATH= %RERANKER_MODEL_PATH%
echo.

:: Check venv
if not exist "venv\Scripts\activate.bat" (
    echo [ERROR] Virtual environment not found.
    echo Please run install\install_intel.bat first.
    goto :FAIL
)
call venv\Scripts\activate.bat

:: Quick dependency check — catch missing packages before launching
echo [INFO] Checking dependencies...
python -c "import faiss, rank_bm25, fastapi, transformers, yaml, psutil, llama_cpp" 2>&1
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] One or more required packages are missing.
    echo Please re-run install\install_intel.bat to repair the installation.
    goto :FAIL
)
echo [OK] Dependencies OK.
echo.

:: Check embedding model (uses EMBED_MODEL_PATH env var set above)
if not exist "%EMBED_MODEL_PATH%\model.safetensors" (
    if not exist "%EMBED_MODEL_PATH%\pytorch_model.bin" (
        echo [ERROR] Embedding model not found at: %EMBED_MODEL_PATH%
        echo         Run install\install_intel.bat or set EMBED_MODEL_PATH to the correct path.
        goto :FAIL
    )
)
echo [OK] Embedding model found.

:: Check LLM model (uses LLM_MODEL_PATH env var set above)
if not exist "%LLM_MODEL_PATH%" (
    echo [ERROR] LLM model not found at: %LLM_MODEL_PATH%
    echo         Update LLM_MODEL_PATH in this launcher or run install\install_intel.bat.
    goto :FAIL
)
echo [OK] LLM model found.

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
echo [INFO] Browser will open automatically once all models are loaded.
echo.

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
