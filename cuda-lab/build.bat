@echo off
setlocal
REM ============================================================
REM  build.bat - compila e roda um programa CUDA na RTX 3050
REM  Uso:   build.bat               (compila vector_add.cu)
REM         build.bat meu_prog.cu   (compila o arquivo informado)
REM  Robusto: usa caminho absoluto (%~dp0 = pasta deste script),
REM  funciona mesmo com NoDefaultCurrentDirectoryInExePath ativo.
REM ============================================================

set "DIR=%~dp0"

REM Arquivo de entrada (padrao: vector_add.cu) e nome de saida
set "SRC=%~1"
set "BASE=%~n1"
if "%~1"=="" set "SRC=vector_add.cu"
if "%~1"=="" set "BASE=vector_add"
set "OUT=%BASE%.exe"

REM 1) Carrega o compilador C++ da Microsoft (cl.exe + Windows SDK)
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul

REM 2) Compila para a arquitetura da RTX 3050 (sm_86) -> sem JIT de PTX
echo [build] Compilando %SRC% para sm_86 ...
nvcc -arch=sm_86 "%DIR%%SRC%" -o "%DIR%%OUT%"
if errorlevel 1 (
    echo [build] ERRO na compilacao.
    exit /b 1
)

echo [build] OK - %OUT%
echo [build] Executando na GPU:
echo ------------------------------------------------------------
"%DIR%%OUT%"
echo ------------------------------------------------------------
endlocal
