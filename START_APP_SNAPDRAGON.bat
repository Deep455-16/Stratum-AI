@echo off
REM ============================================================
REM  START_APP_SNAPDRAGON.bat
REM  Stratum AI — Snapdragon / Qualcomm QNN inference launcher
REM ============================================================
REM  Prerequisites on Snapdragon machine:
REM    pip install -r requirements-intel.txt
REM    pip install -r requirements-snapdragon.txt
REM    huggingface-cli download qualcomm/Qwen3-4B --local-dir models/Qwen3-4B-onnx
REM ============================================================

echo.
echo  ============================================================
echo   STRATUM AI — Snapdragon Backend
echo  ============================================================
echo.

REM Force Snapdragon backend — will error clearly if QNN unavailable
set LLM_BACKEND=snapdragon

REM Default ONNX model path (override with your actual path if different)
if "%SNAPDRAGON_MODEL_PATH%"=="" (
    set SNAPDRAGON_MODEL_PATH=models\Qwen3-4B-onnx
)

REM NPU execution (set to "gpu" or "cpu" if you want to test without NPU)
if "%QNN_BACKEND_TYPE%"=="" (
    set QNN_BACKEND_TYPE=npu
)

REM Keep QNN enabled
set QNN_ENABLED=1

echo  LLM_BACKEND          = %LLM_BACKEND%
echo  SNAPDRAGON_MODEL_PATH = %SNAPDRAGON_MODEL_PATH%
echo  QNN_BACKEND_TYPE     = %QNN_BACKEND_TYPE%
echo.

REM Activate venv if present
if exist venv\Scripts\activate.bat (
    call venv\Scripts\activate.bat
)

echo  Starting Stratum AI server ...
echo  Open http://127.0.0.1:8000 in your browser
echo.

python -m uvicorn server:app --host 127.0.0.1 --port 8000 --workers 1

pause
