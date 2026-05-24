@echo off
setlocal

set PATH=C:\Program Files\LLVM\bin;%PATH%
set B=C:\Users\Lintwer\Desktop\ps5\nicebug\ps5-payload-sdk\install\win

cd /d C:\Users\Lintwer\Desktop\ps5\nicebug\debugger

set CF=-Wall -O2 -I../common/include -Iinclude -Ithird_party/zydis -Ithird_party/keystone/include

echo Building nicebug debugger...

call :cc main || goto :err
call :cc meta || goto :err
call :cc net || goto :err
call :cc console || goto :err
call :cc banner || goto :err
call :cc proc || goto :err
call :cc kern || goto :err
call :cc debug || goto :err
call :cc auth || goto :err
call :cc assemble || goto :err
call :cc hijack_patch_init || goto :err
call :cc kdbg || goto :err
call :cc kern_dbreg || goto :err
call :cc kern_rw_fast || goto :err
call :cc proc_elf || goto :err
call :cc proc_remote || goto :err
call :cc scan || goto :err
call :cc scan_compare || goto :err
call :cc2 sys_proc_rw || goto :err

echo [19] Zydis.c
call %B%\prospero-clang.cmd -O3 -DNDEBUG -DZYAN_NO_LIBC -w -I../common/include -Iinclude -Ithird_party/zydis -c -o build/Zydis.o third_party/zydis/Zydis.c || goto :err

echo [20] Linking...
set SDK=C:\Users\Lintwer\Desktop\ps5\nicebug\ps5-payload-sdk\install

:: Use prospero-clang.cmd as link driver (properly sequences libs and CRT)
call %B%\prospero-clang.cmd ^
  -target x86_64-sie-ps5 ^
  -fno-stack-protector -fno-plt -femulated-tls ^
  -fvisibility-nodllstorageclass=default ^
  --sysroot=%SDK%\target ^
  -isystem %SDK%\target\include ^
  -Wl,--gc-sections -Wl,--no-eh-frame-hdr -Wl,--wrap=__patch_init ^
  -nostartfiles -nodefaultlibs ^
  -o build\debugger.elf ^
  build\main.o build\meta.o build\net.o build\console.o ^
  build\banner.o build\proc.o build\kern.o build\debug.o ^
  build\auth.o build\assemble.o build\hijack_patch_init.o ^
  build\kdbg.o build\kern_dbreg.o build\kern_rw_fast.o ^
  build\proc_elf.o build\proc_remote.o build\scan.o ^
  build\scan_compare.o build\sys_proc_rw.o build\Zydis.o ^
  -Lthird_party\keystone\lib ^
  -Lthird_party\cxxrt\lib ^
  -L%SDK%\target\lib ^
  -lkeystone -lc++ -lc++abi -lunwind -lc ^
  -lSceLibcInternal -lkernel_sys -lSceNet -lSceNetCtl -lSceSysCore ^
  %SDK%\target\lib\crt1.o ^
  %SDK%\target\lib\crti.o ^
  %SDK%\target\lib\crtbegin.o ^
  %SDK%\target\lib\crtend.o ^
  %SDK%\target\lib\crtn.o

if errorlevel 1 goto :err
for %%F in (build\debugger.elf) do echo Built: %%~dpnxF (%%~zF bytes)
echo === BUILD SUCCESS ===
exit /b 0

:cc
echo [%1] %~1.c
call %B%\prospero-clang.cmd %CF% -c -o build\%1.o source\%1.c || exit /b 1
goto :eof

:cc2
echo [%1] %~1.c
call %B%\prospero-clang.cmd %CF% -c -o build\%1.o ..\common\source\%1.c || exit /b 1
goto :eof

:err
echo === BUILD FAILED ===
exit /b 1
