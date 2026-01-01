@echo off
chcp 65001>nul
setlocal enabledelayedexpansion

:request-admin-rights
set adm_arg=%1
if "%adm_arg%" == "admin" (
    title admin
) else (
    echo [93m[powershell] Requesting admin rights...
    powershell -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "Start-Process 'cmd.exe' -ArgumentList '/k \"\"%~f0\" admin\"' -Verb RunAs"
    exit /b
)

choice /C "10" /m "[93m[?] Вы уверены что хотите принудительно добавить RSS и Max Queues на уровне реестра [91mВСЕХ адаптеров [93mв системе?[0m"
if "!errorlevel!"=="1" (echo [90mподтверждено[0m)
if "!errorlevel!"=="2" (goto close)

:do-some-shit
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
try { ^
    $adapters = Get-NetAdapter -ErrorAction Stop; ^
} catch { ^
    Write-Host 'Ошибка при получении списка сетевых адаптеров.' -ForegroundColor Red; ^
    pause; exit 1; ^
} ^
if (-not $adapters) { ^
    Write-Host 'Сетевые адаптеры не найдены.' -ForegroundColor Red; ^
    pause; exit 1; ^
} ^
foreach ($adapter in $adapters) { ^
    Write-Host \"---\" -ForegroundColor Gray; ^
    Write-Host \"Обработка адаптера: $($adapter.Name) ($($adapter.InterfaceDescription))\" -ForegroundColor Gray; ^
    try { ^
        $pnpId = $adapter.PnpDeviceID; ^
        $instId = (Get-ItemProperty \"HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\" -ErrorAction Stop).Driver; ^
        if (-not $instId) { ^
            Write-Host 'Не удалось определить индекс папки в реестре (instId пуст). Пропуск.' -ForegroundColor Yellow; ^
            continue; ^
        } ^
        $path = \"HKLM:\SYSTEM\CurrentControlSet\Control\Class\$instId\"; ^
        if (-not (Test-Path $path)) { ^
            Write-Host \"Путь в реестре не существует: $path. Пропуск.\" -ForegroundColor Yellow; ^
            continue; ^
        } ^
        Write-Host \"Найдена ветка реестра: $path\" -ForegroundColor DarkGray; ^
        ^
        $params = @{ ^
            '*RSS' = '1'; ^
            'RSS' = '1'; ^
            '*RSSProfile' = '1'; ^
            '*NumRssQueues' = '4'; ^
            '*RSSDisplayValue' = 'Enabled' ^
        }; ^
        foreach ($name in $params.Keys) { ^
            Set-ItemProperty -Path $path -Name $name -Value $params[$name] -Force -ErrorAction Stop; ^
        } ^
        ^
        $ndiRss = \"$path\Ndi\Params\*RSS\"; ^
        if (-not (Test-Path $ndiRss)) { New-Item -Path $ndiRss -Force ^| Out-Null; } ^
        Set-ItemProperty -Path $ndiRss -Name 'ParamDesc' -Value 'Receive Side Scaling' -Force; ^
        Set-ItemProperty -Path $ndiRss -Name 'type' -Value 'enum' -Force; ^
        $ePath = \"$ndiRss\enum\"; ^
        if (-not (Test-Path $ePath)) { New-Item -Path $ePath -Force ^| Out-Null; } ^
        Set-ItemProperty -Path $ePath -Name '0' -Value 'Disabled' -Force; ^
        Set-ItemProperty -Path $ePath -Name '1' -Value 'Enabled' -Force; ^
        ^
        $ndiQueues = \"$path\Ndi\Params\*NumRssQueues\"; ^
        if (-not (Test-Path $ndiQueues)) { New-Item -Path $ndiQueues -Force ^| Out-Null; } ^
        Set-ItemProperty -Path $ndiQueues -Name 'ParamDesc' -Value 'Maximum Number of RSS Queues' -Force; ^
        Set-ItemProperty -Path $ndiQueues -Name 'type' -Value 'enum' -Force; ^
        $qEnum = \"$ndiQueues\enum\"; ^
        if (-not (Test-Path $qEnum)) { New-Item -Path $qEnum -Force ^| Out-Null; } ^
        Set-ItemProperty -Path $qEnum -Name '1' -Value '1 Queue' -Force; ^
        Set-ItemProperty -Path $qEnum -Name '2' -Value '2 Queues' -Force; ^
        Set-ItemProperty -Path $qEnum -Name '4' -Value '4 Queues' -Force; ^
        Set-ItemProperty -Path $qEnum -Name '8' -Value '8 Queues' -Force; ^
        ^
        Write-Host 'Настройки RSS и Queues успешно применены.' -ForegroundColor DarkGray; ^
        ^
        try { ^
            $rssStatus = Get-NetAdapterRss -Name $adapter.Name -ErrorAction Stop; ^
            $qCount = $rssStatus.NumberOfReceiveQueues; ^
            Write-Host \"Текущий статус RSS: $($rssStatus.Enabled) | Очередей: $qCount\" -ForegroundColor DarkGray; ^
        } catch { ^
            Write-Host \"Ожидается перезагрузка для активации новых параметров.\" -ForegroundColor Yellow; ^
        } ^
    } catch { ^
        Write-Host \"Ошибка при обработке адаптера $($adapter.Name): $_\" -ForegroundColor Red; ^
    } ^
} 

:close
endlocal
echo.
echo [93mНажмите любую кнопку чтобы закрыть...
timeout /t 30
exit
