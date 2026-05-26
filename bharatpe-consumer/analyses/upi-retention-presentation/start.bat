@echo off
cd /d "%~dp0"
python serve.py 2>nul || py -3 serve.py 2>nul || start "" "upi-retention-results.html"
