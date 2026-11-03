@echo off
if defined BUILD_WORKSPACE_DIRECTORY cd /d "%BUILD_WORKSPACE_DIRECTORY%"
if errorlevel 1 exit /b 1
if not exist ".vscode" mkdir ".vscode"
for %%F in ("%~dpn0.files\*.json") do (
  fc /b "%%~fF" ".vscode\%%~nxF" >nul 2>&1
  if errorlevel 1 (
    copy /Y "%%~fF" ".vscode\%%~nxF" >nul
    if errorlevel 1 exit /b 1
  )
)
fc /b "%~dpn0.files\.bazelrc" ".bazelrc" >nul 2>&1
if errorlevel 1 (
  copy /Y "%~dpn0.files\.bazelrc" ".bazelrc" >nul
  if errorlevel 1 exit /b 1
)
echo Installed Bazel and VS Code configuration.
