chcp 65001>nul
cd /d "%~dp0"
cls
call "bin\autotuninglevel\normal-autotuninglevel.bat"
call "bin\DCA\enable-dca.bat"
call "bin\ECN\enable-ecn.bat"
call "bin\netdma\enable-netdma.bat"
call "bin\RSS\enable-rss.bat"
call "bin\timestamps\enable-timestamps.bat"
pause
