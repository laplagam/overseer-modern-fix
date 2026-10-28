@echo off
rem Builds focusfix as a 32-bit msvfw32.dll. Needs Visual Studio (Build Tools) with the C++ x86 toolset.
setlocal
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq delims=" %%i in (`call "%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (echo Visual Studio C++ build tools not found & exit /b 1)
call "%VS%\VC\Auxiliary\Build\vcvars32.bat" >nul || exit /b 1
cd /d "%~dp0"
if not exist build mkdir build
cl /nologo /O1 /W4 /GS- /LD focusfix.c /Fobuild\ /Fe:build\msvfw32.dll /link /DEF:msvfw32.def /NODEFAULTLIB /ENTRY:DllMain kernel32.lib user32.lib || exit /b 1
if not exist "..\..\bin" mkdir "..\..\bin"
copy /y build\msvfw32.dll "..\..\bin\msvfw32.dll" >nul
echo Built bin\msvfw32.dll
