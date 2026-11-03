@echo off
setlocal DisableDelayedExpansion
if defined BUILD_WORKSPACE_DIRECTORY cd /d "%BUILD_WORKSPACE_DIRECTORY%"
if errorlevel 1 exit /b 1
set "runfiles=%~f0.runfiles"
if defined RUNFILES_DIR set "runfiles=%RUNFILES_DIR%"
set "node=%runfiles%\__NODE__"
set "program=%runfiles%\__PROGRAM__"
if exist "%node%" if exist "%program%" goto run

set "manifest=%~f0.runfiles_manifest"
if defined RUNFILES_MANIFEST_FILE set "manifest=%RUNFILES_MANIFEST_FILE%"
if not exist "%manifest%" (
  echo Web validation runfiles are unavailable 1>&2
  exit /b 1
)
for /f "usebackq tokens=1,* delims= " %%A in ("%manifest%") do (
  if "%%A"=="__NODE__" set "node=%%B"
  if "%%A"=="__PROGRAM__" set "program=%%B"
)

:run
"%node%" "%program%" %*
exit /b %errorlevel%
