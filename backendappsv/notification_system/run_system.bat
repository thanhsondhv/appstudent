@echo off
title VinhUni - He thong thong bao
chcp 65001 >nul
echo.
echo ============================================================
echo   HE THONG THONG BAO VINHUNI
echo ============================================================
echo.

set PYTHON_EXE=..\venv\Scripts\python.exe

:: -----------------------------------------------------------------
:: Kiem tra Redis truoc — thieu Redis thi ca he thong khong chay duoc
:: -----------------------------------------------------------------
%PYTHON_EXE% -c "import redis; redis.Redis().ping()" 2>nul
if errorlevel 1 (
    echo [LOI] Khong ket noi duoc Redis tai localhost:6379
    echo       Hay khoi dong Redis truoc roi chay lai file nay.
    pause
    exit /b 1
)
echo [OK] Redis dang chay
echo.

:: -----------------------------------------------------------------
:: 1. Bo nap hang doi (Producer) — quet SQL, day viec vao Redis
::    Cong 8082. Ban cu dung 8081, trung voi notification_worker.py
::    o thu muc goc nen hai ben khong chay cung luc duoc.
:: -----------------------------------------------------------------
start "BO NAP HANG DOI" cmd /k "%PYTHON_EXE% producer_app.py"
timeout /t 3 >nul

:: -----------------------------------------------------------------
:: 2. Worker lan uu tien cao — chat, nhac lich thi
:: -----------------------------------------------------------------
start "WORKER UU TIEN 1" cmd /k "%PYTHON_EXE% worker_windows.py q_high"
start "WORKER UU TIEN 2" cmd /k "%PYTHON_EXE% worker_windows.py q_high"

:: -----------------------------------------------------------------
:: 3. Worker lan thuong — lich hoc, tin tuc, van ban
:: -----------------------------------------------------------------
start "WORKER THUONG 1" cmd /k "%PYTHON_EXE% worker_windows.py q_default"
start "WORKER THUONG 2" cmd /k "%PYTHON_EXE% worker_windows.py q_default"
start "WORKER THUONG 3" cmd /k "%PYTHON_EXE% worker_windows.py q_default"

echo.
echo [OK] Da khoi dong 1 bo nap + 5 worker
echo.
echo   Theo doi do dai hang doi:
echo     http://localhost:8082/trang-thai-hang-doi
echo   Kiem tra suc khoe:
echo     http://localhost:8082/health
echo.
echo   LUU Y: KHONG chay notification_worker.py o thu muc goc cung luc —
echo          hai ben se gui trung thong bao cho nguoi dung.
echo.
pause
