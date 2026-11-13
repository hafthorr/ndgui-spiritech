@echo off
rem ndGUI for Spiritech - double-click me. Runs install.ps1 (plain PowerShell, readable in any text editor).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
