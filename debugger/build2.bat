@echo off
setlocal

set PATH=C:\Program Files\LLVM\bin;%PATH%
set B=C:\Users\Lintwer\Desktop\ps5\nicebug\ps5-payload-sdk\install\win

cd /d C:\Users\Lintwer\Desktop\ps5\nicebug\debugger

echo [1/21] main.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -Iinclude -Ithird_party/zydis -Ithird_party/keystone/include -c -o build/main.o source/main.c || goto :err
echo [2/21] meta.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -Iinclude -Ithird_party/zydis -Ithird_party/keystone/include -c -o build/meta.o source/meta.c || goto :err
echo [3/21] net.c
call %B%\prospero-clang.cmd -Wall -O2 -I../common/include -Iinclude -Ithird_party/zydis -Ithird_party/keystone/include -c -o build/net.o source/net.c || goto :err
echo Link... done
goto :eof

:err
echo FAILED at previous step
exit /b 1
