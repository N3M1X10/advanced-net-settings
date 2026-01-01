@echo off
chcp 65001>nul

set adm_arg=%1
if "%adm_arg%" == "admin" (
    title admin
) else (
    echo [93m[powershell] Requesting admin rights...
    powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Start-Process 'cmd.exe' -ArgumentList '/k \"\"%~f0\" admin\"' -Verb RunAs"
    exit /b
)



:ask
cls
endlocal
setlocal enabledelayedexpansion
:: Симуляция массива данных для меню
set "menu_items[1]=Включить Cloudflare (1.1.1.1)"
set "menu_items[2]=Включить Google (8.8.8.8)"
set "menu_items[3]=Включить AdGuard DNS (94.140.14.14)"
set "menu_items[4]=Включить Yandex DNS"
set "menu_items[r]=Вернуть DHCP (Автоматический DNS)"
set "menu_items[s]=Открыть настройки сети"
set "menu_items[x]=Выход"

:: Симуляция массива данных для команды choice
echo [93m=========================================
echo [96m        Управление DNS-over-HTTPS
echo [93m=========================================
:: Перебор массива циклом for для вывода меню
for /f "tokens=2 delims=[]" %%i in ('set menu_items[') do (
    echo [96m %%i. !menu_items[%%i]!
    set "choice_keys=!choice_keys!%%i"
)
echo [93m=========================================[0m

:: выбор
echo.
choice /C "!choice_keys!" /n /m "[93m[?] Выберите пункт:[0m"
:: Получаем символ, который нажал пользователь (через подстроку из choice_keys)
set /a "idx=!errorlevel!"
set "user_choice=!choice_keys:~%idx%,1!"
:: Если нажата первая клавиша в списке (1), errorlevel=1. В строке choice_keys это индекс 0.
set /a "idx_fix=!errorlevel!-1"
set "choice=!choice_keys:~%idx_fix%,1!"

:: команды
if "!choice!"=="x" goto close
if "!choice!"=="r" goto disable_doh
if "!choice!"=="s" goto network-ethernet

if "!choice!"=="1" (
    set "ipv4=1.1.1.1,1.0.0.1"
    set "ipv6=2606:4700:4700::1111,2606:4700:4700::1001"
    set "tmpl=one.one.one.one"
    goto apply
)
if "!choice!"=="2" (
    set "ipv4=8.8.8.8,8.8.4.4"
    set "ipv6=2001:4860:4860::8888,2001:4860:4860::8844"
    set "tmpl=dns.google"
    goto apply
)
if "!choice!"=="3" (
    set "ipv4=94.140.14.14,94.140.14.15"
    set "ipv6=2a10:4f:0::a,2a10:4f:0::b"
    set "tmpl=dns.adguard-dns.com"
    goto apply
)
if "!choice!"=="4" (
    set "ipv4=77.88.8.8,77.88.8.1"
    set "ipv6=2a02:6b8::feed:0ff,2a02:6b8:0:1::feed:0ff"
    set "tmpl=common.dns.yandex.net"
    goto apply
)

goto ask



:apply
echo [94m[*] Включение системных политик...[0m
reg add "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" /v "DoHPolicy" /t REG_DWORD /d 2 /f >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v "EnableAutoDoh" /t REG_DWORD /d 2 /f >nul 2>&1

set "v4_list=%ipv4:,= %"
set "v6_list=%ipv6:,= %"
:: Используем обычный %tmpl%, если setlocal enabledelayedexpansion не включен в начале файла
set "full_tmpl=https://%tmpl%/dns-query"

echo [94m[*] Регистрация DoH и привязка IP...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 $ips = ('%ipv4%','%ipv6%').Split(',') ^| Where-Object {$_}; ^
 $tmpl = '%full_tmpl%'; ^
 foreach ($ip in $ips) { ^
     Remove-DNSClientDohServerAddress -ServerAddress $ip -ErrorAction SilentlyContinue; ^
     Add-DNSClientDohServerAddress -ServerAddress $ip -DohTemplate $tmpl -AllowFallbackToUdp $false -AutoUpgrade $true -ErrorAction SilentlyContinue ^| Out-Null; ^
 } ^
 Get-NetAdapter -Physical ^| Where-Object {$_.Status -eq 'Up'} ^| ForEach-Object { ^
     Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ServerAddresses $ips -ErrorAction SilentlyContinue; ^
 }

echo [94m[*] Синхронизация GUI (Doh/Doh6 ключи)...[0m
for /f "tokens=*" %%g in ('powershell -NoProfile -Command "Get-NetAdapter -Physical | Where-Object {$_.Status -eq 'Up'} | Select-Object -ExpandProperty InterfaceGuid"') do (
    for %%i in (%v4_list%) do (
        reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\%%g\DohInterfaceSettings\Doh\%%i" /v "DohFlags" /t REG_QWORD /d 1 /f >nul 2>&1
        netsh dns set encryption server=%%i dohtemplate=%full_tmpl% autoupgrade=yes udpfallback=no >nul 2>&1
    )
    for %%i in (%v6_list%) do (
        reg add "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\%%g\DohInterfaceSettings\Doh6\%%i" /v "DohFlags" /t REG_QWORD /d 1 /f >nul 2>&1
        netsh dns set encryption server=%%i dohtemplate=%full_tmpl% autoupgrade=yes udpfallback=no >nul 2>&1
    )
)

ipconfig /flushdns >nul
echo [94m[*] Проверка интернет-соединения...[0m
:: Ждем 3 секунды, чтобы служба DNS успела инициализироваться
timeout /t 3 /nobreak >nul
ping 1.1.1.1 -n 1 >nul 2>&1
if %errorlevel% neq 0 (
    echo [91m[!] Интернет не работает! Выполняется авто-откат...[0m
    goto disable_doh
)

echo [92mНастройка успешно завершена и проверена.[0m
goto endfunc



:disable_doh
echo [94m[*] Полный откат настроек до заводских...[0m
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
 $doh = Get-DNSClientDohServerAddress -ErrorAction SilentlyContinue; ^
 foreach ($entry in $doh) { Remove-DNSClientDohServerAddress -ServerAddress $entry.ServerAddress -ErrorAction SilentlyContinue }; ^
 Get-NetAdapter -Physical ^| ForEach-Object { ^
     Set-DnsClientServerAddress -InterfaceIndex $_.IfIndex -ResetServerAddresses -ErrorAction SilentlyContinue; ^
     $basePath = \"HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\InterfaceSpecificParameters\$($_.InterfaceGuid)\"; ^
     Remove-Item -Path \"$basePath\DohInterfaceSettings\" -Recurse -ErrorAction SilentlyContinue; ^
 }

reg delete "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" /v "DoHPolicy" /f >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters" /v "EnableAutoDoh" /f >nul 2>&1

:: Очистка зависших настроек netsh для заданных IP
for %%i in (%v4_list% %v6_list%) do (
    netsh dns set encryption server=%%i encryption=no >nul 2>&1
)

ipconfig /flushdns >nul
echo [92mСистема возвращена к заводским настройкам DNS[0m
goto endfunc



:network-ethernet
start ms-settings:network-ethernet
goto ask



:: end of a function
:endfunc
echo.&echo [36m[!time!] Выполнение завершено^^!
echo Нажмите любую кнопку, чтобы вернуться в главное меню...[0m
pause>nul&endlocal&cls
goto :ask



:close
endlocal
exit


