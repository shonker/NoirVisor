@echo off
set path=T:\Program Files\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.27.29110\bin\Hostx64\x64;T:\Program Files\Windows Kits\10\bin\10.0.19041.0\x64;%path%
set incpath=T:\Program Files\Windows Kits\10\Include\10.0.19041.0
set libpath=T:\Program Files\Windows Kits\10\Lib
set binpath=..\bin\compchk_win7x64
set objpath=..\bin\compchk_win7x64\Intermediate

title Compiling NoirVisor, Checked Build, 64-Bit Windows (AMD64 Architecture)
echo Project: NoirVisor
echo Platform: 64-Bit Windows
echo Preset: Debug/Checked Build
echo Powered by zero.tangptr@gmail.com
echo Copyright (c) 2018-2020, zero.tangptr@gmail.com. All Rights Reserved.
pause

echo ============Start Compiling============
echo Compiling Windows Driver Framework...
cl ..\src\booting\windrv\driver.c /I"%incpath%\km\crt" /I"%incpath%\shared" /I"%incpath%\km" /Zi /nologo /W3 /WX /wd4311 /Od /D"_AMD64_" /D"_M_AMD64" /D"_WIN64" /D "_NDEBUG" /D"_UNICODE" /D "UNICODE" /Zc:wchar_t /FAcs /Fa"%objpath%\driver.cod" /Fo"%objpath%\driver.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue

rc /nologo /i"%incpath%\shared" /i"%incpath%\um" /i"%incpath%\km\crt" /fo"%objpath%\version.res" /n ..\src\booting\windrv\version.rc

echo Compiling Core Engine of Intel VT-x...
for %%1 in (..\src\vt_core\*.c) do (cl %%1 /I"..\src\include" /Zi /nologo /W3 /WX /Oi /Od /D"_msvc" /D"_amd64" /D"_vt_core" /D"_%%~n1" /Zc:wchar_t /FAcs /Fa"%objpath%\%%~n1.cod" /Fo"%objpath%\%%~n1.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue)

echo Compiling Core Engine of AMD-V...
for %%1 in (..\src\svm_core\*.c) do (cl %%1 /I"..\src\include" /Zi /nologo /W3 /WX /Oi /Od /D"_msvc" /D"_amd64" /D"_svm_core" /D"_%%~n1" /Zc:wchar_t /FAcs /Fa"%objpath%\%%~n1.cod" /Fo"%objpath%\%%~n1.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue)

echo Compiling Core Engine of Microsoft Hypervisor (MSHV)...
for %%1 in (..\src\mshv_core\*.c) do (cl %%1 /I"..\src\include" /Zi /nologo /W3 /WX /Oi /Od /D"_msvc" /D"_amd64" /D"_mshv_core" /D"_%%~n1" /Zc:wchar_t /FAcs /Fa"%objpath%\%%~n1.cod" /Fo"%objpath%\%%~n1.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue)

echo Compiling Core of Cross-Platform Framework (XPF)...
for %%1 in (..\src\xpf_core\windows\*.c) do (cl %%1 /I"%incpath%\km\crt" /I"%incpath%\shared" /I"%incpath%\km" /Zi /nologo /W3 /WX /Od /D"_KERNEL_MODE" /D"_AMD64_" /D"_M_AMD64" /D"_WIN64" /D "_NDEBUG" /D"_UNICODE" /D "UNICODE" /Zc:wchar_t /FAcs /Fa"%objpath%\%%~n1.cod" /Fo"%objpath%\%%~n1.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue)

cl ..\src\xpf_core\noirhvm.c /I"..\src\include" /Zi /nologo /W3 /WX /Oi /Od /D"_msvc" /D"_amd64" /D"_central_hvm" /Zc:wchar_t /FAcs /Fa"%objpath%\noirhvm.cod" /Fo"%objpath%\noirhvm.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue

cl ..\src\xpf_core\ci.c /I"..\src\include" /Zi /nologo /W3 /WX /Oi /Od /D"_msvc" /D"_amd64" /D"_code_integrity" /Zc:wchar_t /FAcs /Fa"%objpath%\ci.cod" /Fo"%objpath%\ci.obj" /Fd"%objpath%\vc140.pdb" /GS- /Qspectre /TC /c /errorReport:queue

for %%1 in (..\src\xpf_core\windows\*.asm) do (ml64 /W3 /WX /D"_amd64" /Zf /Zd /Fo"%objpath%\%%~n1.obj" /c /nologo %%1)

echo ============Start Linking============
link "%objpath%\*.obj" "%objpath%\version.res" /LIBPATH:"%libpath%\win7\km\x64" /NODEFAULTLIB "ntoskrnl.lib" "..\src\disasm\bin\compchk_win7x64\zydis.lib" /NOLOGO /DEBUG /PDB:"%objpath%\NoirVisor.pdb" /OUT:"%binpath%\NoirVisor.sys" /SUBSYSTEM:NATIVE /Driver /ENTRY:"NoirDriverEntry" /Machine:X64 /ERRORREPORT:QUEUE

echo ============Start Signing============
signtool sign /v /f .\ztnxtest.pfx /t http://timestamp.globalsign.com/scripts/timestamp.dll %binpath%\NoirVisor.sys

pause