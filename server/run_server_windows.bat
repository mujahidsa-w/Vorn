@echo off
rem AURUM MOBILE online server on a Windows PC.
rem 1) Download Godot 4.6.2 (Windows, standard) from godotengine.org and put Godot_v4.6.2-stable_win64_console.exe in this folder.
rem 2) Double-click this file. Allow it through the Windows firewall, and forward UDP 24600-24640 on the router.
cd /d "%~dp0\.."
set GODOT=%~dp0Godot_v4.6.2-stable_win64_console.exe
"%GODOT%" --headless --path . --import
if not exist server_data mkdir server_data
:loop
"%GODOT%" --headless --path . -- --server --data "%cd%\server_data"
echo server stopped, restarting...
timeout /t 3 >nul
goto loop
