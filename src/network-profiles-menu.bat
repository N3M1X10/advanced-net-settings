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
echo [90m[^>] Настройка TCP/IP стека и RSC...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1'; $debug = '%DEBUG_MODE%';" ^
    "$bbr = (netsh int tcp show supplemental) -match 'bbr';" ^
    "$provider = if ($mode -eq '1' -and $bbr) { 'bbr' } elseif ($mode -eq '1') { 'cubic' } else { 'ctcp' };" ^
    "if ($mode -eq '1') {" ^
    "    netsh int tcp set global rss=enabled rsc=disabled fastopen=enabled autotuninglevel=normal ecncapability=disabled timestamps=disabled initialrto=2000 >$null 2>&1;" ^
    "    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Disable-NetAdapterRsc -ErrorAction SilentlyContinue;" ^
    "    $templates = @('internet','datacenter','compat','custom');" ^
    "    foreach ($t in $templates) { netsh int tcp set supplemental template=$t congestionprovider=$provider >$null 2>&1; }" ^
    "    netsh int tcp set global dca=disabled netdma=disabled >$null 2>&1;" ^
    "} elseif ($mode -eq 'download') {" ^
    "    netsh int tcp set global rss=enabled rsc=enabled fastopen=enabled autotuninglevel=normal ecncapability=enabled timestamps=disabled initialrto=3000 >$null 2>&1;" ^
    "    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Enable-NetAdapterRsc -ErrorAction SilentlyContinue;" ^
    "    netsh int tcp set supplemental template=internet congestionprovider=ctcp >$null 2>&1;" ^
    "} elseif ($mode -eq 'reset' -or $mode -eq '0') {" ^
    "    netsh int ip reset >$null 2>&1; netsh int tcp reset >$null 2>&1; netsh winsock reset >$null 2>&1;" ^
    "    Get-NetAdapter -Physical | Where-Object Status -eq 'Up' | Enable-NetAdapterRsc -ErrorAction SilentlyContinue;" ^
    "    netsh int tcp set global autotuninglevel=normal rss=enabled rsc=enabled >$null 2>&1;" ^
    "}"
exit /b


:adapter_tuning
:: %1: 1 - твик, 0 - дефолт
echo [90m[^>] Настройка свойств сетевых адаптеров...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1'; $debug = '%DEBUG_MODE%';" ^
    "$cpuCores = [Environment]::ProcessorCount;" ^
    "$rssQueues = [Math]::Max(1, [Math]::Min(4, [Math]::Floor($cpuCores / 2)));" ^
    "Get-NetAdapter -Physical | Where-Object { $_.Status -eq 'Up' } | ForEach-Object {" ^
    "    $n = $_.Name;" ^
    "    if ($mode -eq '1') {" ^
    "        $props = @{'*InterruptModeration'='0'; '*FlowControl'='0'; '*EEE'='0'; '*NumRSSQueues'=$rssQueues; '*RSS'='1'}" ^
    "    } else {" ^
    "        $props = @{'*InterruptModeration'='1'; '*FlowControl'='3'; '*EEE'='1'; '*RSS'='1'}" ^
    "    }" ^
    "    foreach ($item in $props.GetEnumerator()) {" ^
    "        $k = $item.Key; $val = [string]$item.Value;" ^
    "        try {" ^
    "            $current = Get-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $k -ErrorAction SilentlyContinue;" ^
    "            if ($current -and ($current.RegistryValue -ne $val)) {" ^
    "                Set-NetAdapterAdvancedProperty -Name $n -RegistryKeyword $k -RegistryValue $val -NoRestart -ErrorAction SilentlyContinue;" ^
    "                if ($debug -eq '1') { Write-Host (' [DEBUG] ' + $n + ' : ' + $k + ' -> ' + $val) -Fore Gray }" ^
    "            }" ^
    "        } catch { }" ^
    "    }" ^
    "}"
exit /b


:nagle
:: %1: 1 - твик, 0/reset - дефолт
echo [90m[^>] Настройка алгоритма Nagle...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1'; $debug = '%DEBUG_MODE%';" ^
    "$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces';" ^
    "Get-ChildItem -Path $regPath | ForEach-Object {" ^
    "    $path = $_.PSPath;" ^
    "    $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue;" ^
    "    if ($props.IPAddress -or $props.DhcpIPAddress) {" ^
    "        if ($mode -eq '1') {" ^
    "            Set-ItemProperty -Path $path -Name 'TcpAckFrequency' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "            Set-ItemProperty -Path $path -Name 'TCPNoDelay' -Value 1 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "            Set-ItemProperty -Path $path -Name 'TcpDelAckTicks' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "            if ($debug -eq '1') { Write-Host \" [DEBUG] Nagle отключен для: $($_.PSChildName)\" -Fore Gray };" ^
    "        } else {" ^
    "            foreach ($name in @('TcpAckFrequency', 'TCPNoDelay', 'TcpDelAckTicks')) {" ^
    "                if ($props.PSObject.Properties[$name]) {" ^
    "                    Remove-ItemProperty -Path $path -Name $name -Force -ErrorAction SilentlyContinue;" ^
    "                }" ^
    "            }" ^
    "            if ($debug -eq '1') { Write-Host \" [DEBUG] Nagle сброшен для: $($_.PSChildName)\" -Fore Gray };" ^
    "        }" ^
    "    }" ^
    "}"
exit /b


:multimedia
:: %1: gaming - игровой профиль, 0/reset - стандартный профиль
echo [90m[^>] Настройка приоритетов Multimedia/Games...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1';" ^
    "$regPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile';" ^
    "$regPathGames = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Games';" ^
    "if ($mode -eq 'gaming') {" ^
    "    Set-ItemProperty -Path $regPath -Name 'NetworkThrottlingIndex' -Value 4294967295 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPath -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    if (-not (Test-Path $regPathGames)) { New-Item -Path $regPathGames -Force | Out-Null };" ^
    "    Set-ItemProperty -Path $regPathGames -Name 'GPU Priority' -Value 8 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPathGames -Name 'Priority' -Value 6 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "} else {" ^
    "    Set-ItemProperty -Path $regPath -Name 'NetworkThrottlingIndex' -Value 10 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPath -Name 'SystemResponsiveness' -Value 20 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPathGames -Name 'Priority' -Value 2 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "}"
exit /b


:tcp_params
:: %1: 1 - твик (игры), reset/0 - удаление ключей (дефолт)
echo [90m[^>] Настройка лимитов TCP портов...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1';" ^
    "$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters';" ^
    "if ($mode -eq '1') {" ^
    "    Set-ItemProperty -Path $regPath -Name 'MaxUserPort' -Value 65534 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPath -Name 'TcpMaxDataRetransmissions' -Value 5 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "    Set-ItemProperty -Path $regPath -Name 'TcpTimedWaitDelay' -Value 30 -Type DWord -Force -ErrorAction SilentlyContinue;" ^
    "} else {" ^
    "    foreach ($name in @('MaxUserPort', 'TcpMaxDataRetransmissions', 'TcpTimedWaitDelay')) {" ^
    "        if (Get-ItemProperty -Path $regPath -Name $name -ErrorAction SilentlyContinue) {" ^
    "            Remove-ItemProperty -Path $regPath -Name $name -Force -ErrorAction SilentlyContinue;" ^
    "        }" ^
    "    }" ^
    "}"
exit /b


:qos_tuning
:: %1: 1 - убрать лимит (1%), reset - вернуть 20%
echo [90m[^>] Настройка планировщика пакетов QoS...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$mode = '%~1';" ^
    "$path = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched';" ^
    "if ($mode -eq '1') {" ^
    "    if (-not (Test-Path $path)) { New-Item -Path $path -Force ^| Out-Null };" ^
    "    Set-ItemProperty -Path $path -Name 'NonBestEffortLimit' -Value 1 -Type DWord -Force;" ^
    "} else {" ^
    "    if (Test-Path $path) { Remove-ItemProperty -Path $path -Name 'NonBestEffortLimit' -Force -ErrorAction SilentlyContinue };" ^
    "}"
exit /b


:restart_net_adapter
echo.
echo [90m[^>] Перезапуск сетевых адаптеров...
rem netsh interface set interface "Ethernet" disable>nul
rem netsh interface set interface "Ethernet" enable>nul
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 "Get-NetConnectionProfile | Where-Object { $_.IPv4Connectivity -eq 'Internet' -or $_.IPv6Connectivity -eq 'Internet' } | Get-NetAdapter | Restart-NetAdapter -Confirm:$false"
ipconfig /flushdns >nul 2>&1
echo Готово.
pause




:: end of a function
:endfunc
echo.&echo [36m[!time!] Выполнение завершено^^!
if !exaf!==1 (endlocal&exit/b)
echo Нажмите любую кнопку, чтобы вернуться в главное меню...[0m
pause>nul&endlocal&cls
goto :menu


