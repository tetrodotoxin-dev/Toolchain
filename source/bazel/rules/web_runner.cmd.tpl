@echo off
setlocal DisableDelayedExpansion
set "runfiles=%~f0.runfiles"
if defined RUNFILES_DIR set "runfiles=%RUNFILES_DIR%"
set "node=%runfiles%\_main\__NODE__"
set "program=%runfiles%\_main\__PROGRAM__"
if exist "%node%" if exist "%program%" goto run

set "manifest=%~f0.runfiles_manifest"
if defined RUNFILES_MANIFEST_FILE set "manifest=%RUNFILES_MANIFEST_FILE%"
if not exist "%manifest%" (
  echo Web validation runfiles are unavailable 1>&2
  exit /b 1
)
for /f "usebackq tokens=1,* delims= " %%A in ("%manifest%") do (
  if "%%A"=="__NODE_RLOCATION__" set "node=%%B"
  if "%%A"=="__PROGRAM_RLOCATION__" set "program=%%B"
)

:run
"%node%" "%program%" %*
exit /b %errorlevel%
