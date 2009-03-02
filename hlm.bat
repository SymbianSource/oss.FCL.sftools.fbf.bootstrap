@echo off
setlocal
if not defined HELIUM_HOME set HELIUM_HOME=%~dp0..\..\..\..\helium
echo %HELIUM_HOME%
call %HELIUM_HOME%\hlm.bat %*
endlocal


        