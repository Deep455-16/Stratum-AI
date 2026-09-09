@echo off
:: ============================================================
::  INSTALL.bat  (root redirector — do not delete)
::  Redirects to install\install_intel.bat
:: ============================================================
::  For organised installers see the  install\  folder:
::    install\install_intel.bat      — Intel / CPU setup
::    install\install_snapdragon.bat — Snapdragon / QNN setup
:: ============================================================
echo.
echo  Redirecting to install\install_intel.bat ...
echo.
call "%~dp0install\install_intel.bat"
