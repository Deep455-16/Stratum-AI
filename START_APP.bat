@echo off
:: ============================================================
::  START_APP.bat  (root redirector — do not delete)
::  Redirects to launchers\start_intel.bat
:: ============================================================
::  For organised launchers see the  launchers\  folder:
::    launchers\start_intel.bat      — Intel / CPU (llama.cpp)
::    launchers\start_snapdragon.bat — Snapdragon NPU (QNN)
:: ============================================================
echo.
echo  Redirecting to launchers\start_intel.bat ...
echo.
call "%~dp0launchers\start_intel.bat"
