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



:menu
setlocal enabledelayedexpansion
set "DEBUG_MODE="
cls
set "choice_keys="
:: Конфигурация меню (Массив данных)
set "menu_items[1]=GAMING: Max Responsiveness"
set "menu_items[2]=DOWNLOAD: Max Throughput"
set "menu_items[3]=RESTORE: Factory Defaults"
set "menu_items[x]=Выход"

echo [93m========================================[0m
echo [96m        Network Profiles Manager
echo [93m========================================[0m

:: Автоматический вывод меню из массива
for /f "tokens=2 delims=[]" %%i in ('set menu_items[') do (
    echo [96m %%i. !menu_items[%%i]![0m
    set "choice_keys=!choice_keys!%%i"
)
echo [93m========================================[0m

echo.
choice /C "!choice_keys!" /n /m "[93m[?] Выберите пункт:[0m"
set /a "idx_fix=!errorlevel!-1"
set "choice=!choice_keys:~%idx_fix%,1!"

if "%choice%"=="1" goto mode_gaming
if "%choice%"=="2" goto mode_download
if "%choice%"=="3" goto mode_default
if /i "%choice%"=="x" endlocal&exit
goto menu


:mode_gaming
cls
echo [90m[^>] Применяю игровой профиль...[0m

call :network_stack "1"
call :adapter_tuning "1"
call :nagle "1"
call :multimedia "gaming"
call :tcp_params "1"
call :qos_tuning "1"

call :restart_net_adapter
echo.
echo Оптимизация завершена!
goto endfunc


:mode_download
cls
echo [90m[^>] Применяю профиль максимальной скорости...[0m
call :network_stack "download"
call :adapter_tuning "1"
call :tcp_params "1"
call :qos_tuning "1"
call :nagle "reset"
call :multimedia "reset"

call :restart_net_adapter
echo.
echo Готово!
goto endfunc


:mode_default
cls
echo [90m[^>] Возврат к заводским настройкам (Гарантировано)...[0m

call :network_stack "reset"
call :adapter_tuning "reset"
call :nagle "reset"
call :multimedia "reset"
call :tcp_params "reset"
call :qos_tuning "reset"

call :restart_net_adapter
echo.
echo Сброс завершен.
goto endfunc



:: --- ФУНКЦИИ-ДЕЛЕГАТЫ ---

:network_stack
:: %1: 1 (игры), download (скорость), 0 (стандарт), reset (сброс)
echo [90m[^>] Настройка TCP/IP стека...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1'; $debug = '%DEBUG_MODE%';" ^
    "$bbr = (netsh int tcp show supplemental) -match 'bbr';" ^
    "$provider = if ($mode -eq '1' -and $bbr) { 'bbr' } elseif ($mode -eq '1') { 'cubic' } else { 'ctcp' };" ^
    "if ($debug -eq '1') { Write-Host \" [DEBUG] Провайдер: $provider\" -Fore Gray };" ^
    "if ($mode -eq '1') {" ^
    "    netsh int tcp set global rss=enabled rsc=disabled fastopen=enabled autotuninglevel=normal ecncapability=disabled timestamps=disabled initialrto=2000 >$null 2>&1;" ^
    "    netsh int tcp set supplemental template=custom congestionprovider=$provider >$null 2>&1;" ^
    "    netsh int tcp set global dca=disabled >$null 2>&1; netsh int tcp set global netdma=disabled >$null 2>&1;" ^
    "} elseif ($mode -eq 'download') {" ^
    "    netsh int tcp set global rss=enabled rsc=enabled fastopen=enabled autotuninglevel=normal ecncapability=enabled timestamps=disabled initialrto=3000 >$null 2>&1;" ^
    "    netsh int tcp set supplemental template=custom congestionprovider=ctcp >$null 2>&1;" ^
    "} elseif ($mode -eq 'reset') {" ^
    "    netsh int ip reset >$null 2>&1; netsh int tcp reset >$null 2>&1; netsh winsock reset >$null 2>&1;" ^
    "}"
exit /b


:adapter_tuning
:: %1: 1 - твик, 0/reset - дефолт
echo [90m[^>] Настройка свойств сетевых адаптеров (PS)...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1'; $debug = '%DEBUG_MODE%';" ^
    "$cpuCores = [Environment]::ProcessorCount;" ^
    "$rssQueues = [Math]::Max(1, [Math]::Min(4, [Math]::Floor($cpuCores / 2)));" ^
    "Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Physical } | ForEach-Object {" ^
    "    $n = $_.Name;" ^
    "    $props = if ($mode -eq '1') { @{'*InterruptModeration'='0'; '*FlowControl'='0'; '*EEE'='0'; '*NumRssQueues'=\"$rssQueues\"; '*RSS'='1'} } " ^
    "             else { @{'*InterruptModeration'='1'; '*FlowControl'='3'; '*EEE'='1'; '*RSS'='1'} };" ^
    "    foreach ($k in $props.Keys) {" ^
    "        $current = Get-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $k -ErrorAction SilentlyContinue;" ^
    "        if ($current -and $current.RegistryValue -ne $props[$k]) {" ^
    "            if ($debug -eq '1') { Write-Host (' [DEBUG] ' + $n + ' : ' + $k + ' -> ' + $props[$k]) -Fore Gray };" ^
    "            Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $k -RegistryValue $props[$k] -NoRestart -ErrorAction SilentlyContinue;" ^
    "        }" ^
    "    }" ^
    "    if ($mode -eq '1') { Disable-NetAdapterPowerManagement -Name $n -ErrorAction SilentlyContinue }" ^
    "    else { Enable-NetAdapterPowerManagement -Name $n -ErrorAction SilentlyContinue }" ^
    "}"
exit /b


:nagle
:: %1: 1 - твик, 0/reset - дефолт
echo [90m[^>] Настройка алгоритма Nagle...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1';" ^
    "$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\';" ^
    "Get-ChildItem -Path $regPath | ForEach-Object {" ^
    "    $path = $_.PSPath;" ^
    "    $isIface = Get-ItemProperty -Path $path -Name 'IPAddress', 'DhcpIPAddress' -ErrorAction SilentlyContinue;" ^
    "    if ($isIface) {" ^
    "        if ($mode -eq '1') {" ^
    "            Set-ItemProperty -Path $path -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "            Set-ItemProperty -Path $path -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "            Set-ItemProperty -Path $path -Name 'TcpDelAckTicks' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "        } else {" ^
    "            Remove-ItemProperty -Path $path -Name 'TcpAckFrequency', 'TCPNoDelay', 'TcpDelAckTicks' -Force -ErrorAction SilentlyContinue;" ^
    "        }" ^
    "    }" ^
    "}"
exit /b


:multimedia
echo [90m[^>] Настройка приоритетов Multimedia/Games...[0m
setlocal
set "regPath=HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
if "%~1"=="gaming" (
    :: Проверяем только один ключ для экономии времени, если он ок - считаем что профиль применен
    for /f "tokens=3" %%a in ('reg query "%regPath%" /v SystemResponsiveness 2^>nul') do if "%%a"=="0x0" goto :skip_multimedia
    reg add "%regPath%" /v NetworkThrottlingIndex /t REG_DWORD /d 4294967295 /f >nul
    reg add "%regPath%" /v SystemResponsiveness /t REG_DWORD /d 0 /f >nul
    reg add "%regPath%\Tasks\Games" /v "GPU Priority" /t REG_DWORD /d 8 /f >nul
    reg add "%regPath%\Tasks\Games" /v Priority /t REG_DWORD /d 6 /f >nul
) else (
    reg add "%regPath%" /v NetworkThrottlingIndex /t REG_DWORD /d 10 /f >nul
    reg add "%regPath%" /v SystemResponsiveness /t REG_DWORD /d 20 /f >nul
    reg add "%regPath%\Tasks\Games" /v Priority /t REG_DWORD /d 2 /f >nul
)
:skip_multimedia
endlocal
exit /b


:tcp_params
:: %1: 1 - твик, reset/0 - удаление ключей (дефолт)
echo [90m[^>] Настройка лимитов TCP портов...[0m
if "%~1"=="1" (
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v MaxUserPort /t REG_DWORD /d 65534 /f >nul
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxDataRetransmissions /t REG_DWORD /d 5 /f >nul
    reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpTimedWaitDelay /t REG_DWORD /d 30 /f >nul
) else (
    reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v MaxUserPort /f >nul 2>&1
    reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpMaxDataRetransmissions /f >nul 2>&1
    reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v TcpTimedWaitDelay /f >nul 2>&1
)
exit /b


:qos_tuning
:: %1: 1 - убрать лимит, reset - вернуть 20%
echo [90m[^>] Настройка планировщика пакетов QoS...[0m
if "%~1"=="1" (
    reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched" /v NonBestEffortLimit /t REG_DWORD /d 0 /f >nul 2>&1
) else (
    reg delete "HKLM\SOFTWARE\Policies\Microsoft\Windows\Psched" /v NonBestEffortLimit /f >nul 2>&1
)
exit /b


:restart_net_adapter
echo.
echo [90m[^>] Перезапуск сетевых адаптеров...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -and $_.Physical } | Restart-NetAdapter -Confirm:$false"
ipconfig /flushdns >nul 2>&1
echo Готово[0m
exit /b



:: end of a function
:endfunc
echo.&echo [36m[!time!] Выполнение завершено^^!
if !exaf!==1 (endlocal&exit/b)
echo Нажмите любую кнопку, чтобы вернуться в главное меню...[0m
pause>nul&endlocal&cls
goto :menu


