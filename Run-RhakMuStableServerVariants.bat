@echo off
cd /d "%~dp0"
echo Starting RhakMu stable server with all game-start variants...
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Start-RhakMuStableServer.ps1" -GameStartSyncMode original-plus-variants
pause
