@echo off
if not exist ".vscode" mkdir ".vscode"
for %%F in ("%~dpn0.files\*.json") do (
  copy /Y "%%~fF" ".vscode\%%~nxF" >nul
  if errorlevel 1 exit /b 1
)
call "%~dp0format.cmd" --export-configuration ".vscode\.clang-format"
if errorlevel 1 exit /b 1
