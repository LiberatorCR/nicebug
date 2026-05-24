@echo off
setlocal

set PATH=C:\Program Files\LLVM\bin;%PATH%
set B=C:\Users\Lintwer\Desktop\ps5\nicebug\ps5-payload-sdk\install\win

cd /d C:\Users\Lintwer\Desktop\ps5\nicebug\installer

:: Step 1: Embed debugger.elf into the installer binary
echo [1/6] Embedding debugger.elf...
mkdir build 2>nul
copy /Y ..\debugger\build\debugger.elf build\embedded_inner.elf.bin >nul

:: Step 2: Make build dir
mkdir build 2>nul

:: Step 3: Assemble the embedded ELF blob
echo [2/6] Assembling embedded_inner.S...
call %B%\prospero-clang.cmd -c -o build\embedded_inner.o source\embedded_inner.S -Ibuild || goto :err

:: Step 4: Compile installer C sources
echo [3/6] main.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -c -o build\main.o source\main.c || goto :err
echo [4/6] kern_rw_fast.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -c -o build\kern_rw_fast.o source\kern_rw_fast.c || goto :err
echo [5/6] stubs.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -c -o build\stubs.o source\stubs.c || goto :err
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -I../debugger/include -c -o build\proc_elf.o source\proc_elf.c || goto :err
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -I../debugger/include -I../debugger/third_party/keystone/include -c -o build\proc_remote.o source\proc_remote.c || goto :err
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -ffunction-sections -fdata-sections -c -o build\find_pid.o source\find_pid.c || goto :err
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -I../debugger/include -ffunction-sections -fdata-sections -c -o build\sys_proc_rw.o ..\common\source\sys_proc_rw.c || goto :err

set SDK=C:\Users\Lintwer\Desktop\ps5\nicebug\ps5-payload-sdk\install

echo [6/6] Linking installer...
call %B%\prospero-clang.cmd ^
  -target x86_64-sie-ps5 ^
  -fno-stack-protector -fno-plt -femulated-tls ^
  -fvisibility-nodllstorageclass=default ^
  --sysroot=%SDK%\target ^
  -isystem %SDK%\target\include ^
  -Wall -O2 ^
  -ffunction-sections -fdata-sections ^
  -Wl,--gc-sections ^
  -nostartfiles -nodefaultlibs ^
  -o build\ps5debug-NG.elf ^
  build\main.o build\kern_rw_fast.o build\stubs.o build\proc_elf.o build\proc_remote.o build\find_pid.o build\sys_proc_rw.o build\embedded_inner.o ^
  -Lthird_party\cxxrt\lib ^
  -L%SDK%\target\lib ^
  -lc++ -lc++abi -lunwind -lc ^
  -lSceLibcInternal -lkernel_sys -lSceNet -lSceNetCtl -lSceSysCore ^
  %SDK%\target\lib\crt1.o ^
  %SDK%\target\lib\crti.o ^
  %SDK%\target\lib\crtbegin.o ^
  %SDK%\target\lib\crtend.o ^
  %SDK%\target\lib\crtn.o

if errorlevel 1 goto :err
for %%F in (build\ps5debug-NG.elf) do echo Built: %%~dpnxF (%%~zF bytes)
echo === INSTALLER BUILD SUCCESS ===
exit /b 0

:err
echo === INSTALLER BUILD FAILED ===
exit /b 1
