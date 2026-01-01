@echo off
chcp 65001 >nul

cd /d "%~dp0"

set adm_arg=%1
if "%adm_arg%" == "admin" (
    title admin
) else (
    echo [93m[powershell] Requesting admin rights...
    powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Start-Process 'cmd.exe' -ArgumentList '/k \"\"%~f0\" admin\"' -Verb RunAs"
    exit /b
)

:: Проверка прав администратора
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo ОШИБКА: Запустите файл от имени Администратора!
    pause
    exit /b
)

:menu
setlocal enabledelayedexpansion
cls
set "choice_keys="
:: Конфигурация меню (Массив данных)
set "menu_items[1]=GAMING: Max Responsiveness"
set "menu_items[2]=DOWNLOAD: Max Throughput"
set "menu_items[3]=RESTORE: Factory Defaults"
set "menu_items[x]=Выход"

echo [93m=========================================[0m
echo [96m       ВЫБОР РЕЖИМА НАСТРОЙКИ СЕТИ      [0m
echo [93m=========================================[0m

:: Автоматический вывод меню из массива
for /f "tokens=2 delims=[]" %%i in ('set menu_items[') do (
    echo [96m %%i. !menu_items[%%i]![0m
    set "choice_keys=!choice_keys!%%i"
)
echo [93m=========================================[0m

echo.
choice /C "!choice_keys!" /n /m "[93m[?] Выберите пункт:[0m"
set /a "idx_fix=!errorlevel!-1"
set "choice=!choice_keys:~%idx_fix%,1!"

if "%choice%"=="1" goto mode_gaming
if "%choice%"=="2" goto mode_download
if "%choice%"=="3" goto mode_default
if /i "%choice%"=="x" endlocal&exit
goto menu


:: end of a function
:endfunc
echo.&echo [36m[!time!] Выполнение завершено^^!
if !exaf!==1 (endlocal&exit/b)
echo Нажмите любую кнопку, чтобы вернуться в главное меню...[0m
pause>nul&endlocal&cls
goto :menu


:mode_gaming
cls
echo [^>] Применяю игровой профиль...
call :set_autotuning "normal"
call :set_fastopen "1"
call :set_dca "1"
call :set_ecn "0"
call :set_rss "1"
call :set_rsc "0"
call :set_nodelay "1"

:: Доп. настройки через реестр и PS
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
 "$a = Get-NetAdapter | Where-Object Status -eq 'Up';" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*InterruptModeration' -RegistryValue '0' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*PriorityVLANTag' -RegistryValue '0' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*ReceiveSideScaling' -RegistryValue '1' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*FlowControl' -RegistryValue '0' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*NumRssQueues' -RegistryValue '4' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*EEE' -RegistryValue '0' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Set-NetAdapterAdvancedProperty -RegistryKeyword '*IdleRestriction' -RegistryValue '0' -ErrorAction SilentlyContinue | Out-Null;" ^
 "$a | Disable-NetAdapterPowerManagement;" ^
 "exit 0;"

reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 0xffffffff /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "SystemResponsiveness" /t REG_DWORD /d 0 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "MaxUserPort" /t REG_DWORD /d 65534 /f >nul
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "TcpMaxDataRetransmissions" /t REG_DWORD /d 2 /f >nul

call :restart_net_adapter

echo.
echo Готово^^!
goto endfunc



:mode_download
:: Throughput
cls
echo [^>] Применяю профиль для закачек...
call :set_autotuning "normal"
call :set_dca "1"
call :set_ecn "0"
call :set_rss "1"
call :set_rsc "1"
call :set_timestamps "1"
call :set_nodelay "0"

powershell -Command "Get-NetAdapter | Where-Object Status -eq 'Up' | Set-NetAdapterAdvancedProperty -RegistryKeyword '*InterruptModeration' -RegistryValue '1' -ErrorAction SilentlyContinue | Out-Null"
:: Настройка TCP Window
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v "TcpWindowSize" /t REG_DWORD /d 65535 /f >nul
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v "NetworkThrottlingIndex" /t REG_DWORD /d 10 /f

call :restart_net_adapter

echo.
echo Готово!
goto endfunc



:mode_default
:: Restore defaults
cls
echo [^>] Возврат к заводским настройкам Windows ...

:: Очистка DNS
ipconfig /flushdns >nul
:: Сброс IP/TCP
netsh int ip reset >nul
netsh int tcp reset >nul
:: Сброс Winsock
netsh winsock reset >nul
:: Cброс шаблонов TCP
netsh int tcp set supplemental template=internet setup
netsh int tcp set global autotuninglevel=normal
:: Удаляем пользовательские реестровые ключи
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v NetworkThrottlingIndex /f >nul
reg delete "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" /v SystemResponsiveness /f >nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v MaxUserPort /f >nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxDataRetransmissions /f >nul
for /F "tokens=1,2*" %%i in ('reg query HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces /s ^| findstr /I "Interface"') do (
    reg delete "%%j" /v TcpAckFrequency /f 2>nul
    reg delete "%%j" /v TCPNoDelay /f 2>nul
    reg delete "%%j" /v TcpDelAckTicks /f 2>nul
)

call :restart_net_adapter

echo Сброс завершён. Перезагрузите компьютер, чтобы изменения вступили в силу.
goto endfunc


:restart_net_adapter
echo.&echo [90mперезапуск сетевого адаптера...[0m
powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -Command ^
Get-NetAdapter ^| Where-Object { $_.Status -eq 'Up' } ^| Restart-NetAdapter -Confirm^:$false
exit/b


:set_autotuning
netsh int tcp set global autotuninglevel=%~1 >nul
exit /b


:set_ecn
if "%~1"=="0" (
    netsh int tcp set global ecncapability=disabled >nul 2>&1
) else (
    netsh int tcp set global ecncapability=enabled >nul 2>&1
)
exit /b


:set_dca
if "%~1"=="0" (netsh int tcp set global dca=disabled >nul) else (netsh int tcp set global dca=enabled >nul)
exit /b


:set_rss
if "%~1"=="0" (
    netsh int tcp set global rss=disabled >nul
    powershell -Command "Disable-NetAdapterRss -Name '*'" >nul 2>&1
) else (
    netsh int tcp set global rss=enabled >nul
    powershell -Command "Enable-NetAdapterRss -Name '*'" >nul 2>&1
)
exit /b


:set_rsc
if "%~1"=="0" (
    netsh int tcp set global rsc=disabled >nul
    powershell -Command "Disable-NetAdapterRsc -Name '*'" >nul 2>&1
) else (
    netsh int tcp set global rsc=enabled >nul
    powershell -Command "Enable-NetAdapterRsc -Name '*'" >nul 2>&1
)
exit /b


:set_timestamps
if "%~1"=="0" (netsh int tcp set global timestamps=disabled >nul) else (netsh int tcp set global timestamps=enabled >nul)
exit /b


:set_nodelay
if "%~1"=="1" (
    for /f %%i in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"') do (
        reg add "%%i" /v "TcpAckFrequency" /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "%%i" /v "TCPNoDelay" /t REG_DWORD /d 1 /f >nul 2>&1
        reg add "%%i" /v "TcpDelAckTicks" /t REG_DWORD /d 0 /f >nul 2>&1
    )
) else (
    for /f %%i in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"') do (
        reg delete "%%i" /v "TcpAckFrequency" /f >nul 2>&1
        reg delete "%%i" /v "TCPNoDelay" /f >nul 2>&1
        reg delete "%%i" /v "TcpDelAckTicks" /f >nul 2>&1
    )
)
exit /b


:set_fastopen
if "%~1"=="0" (
    netsh int tcp set global fastopen=disabled >nul
) else (
    netsh int tcp set global fastopen=enabled >nul
)
exit /b
