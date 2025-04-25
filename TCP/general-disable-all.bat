chcp 65001>nul
cd /d "%~dp0"
cls
call "bin\autotuninglevel\disable-autotuninglevel.bat"
call "bin\DCA\disable-dca.bat"
call "bin\ECN\disable-ecn.bat"
call "bin\netdma\disable-netdma.bat"
call "bin\RSS\disable-rss.bat"
call "bin\timestamps\disable-timestamps.bat"
pause
