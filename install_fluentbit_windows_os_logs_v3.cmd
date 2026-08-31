@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM Fluent Bit Windows OS Log Agent Installer v3
REM CMD ONLY - NO POWERSHELL REQUIRED
REM ============================================================

REM Loki endpoint
set "LOKI_HOST=192.168.114.75"
set "LOKI_PORT=80"
set "LOKI_URI=/loki/api/v1/push"

REM Your screenshot shows the Fluent Bit installer EXE is directly
REM inside D:\MASTER, not inside a folder.
set "MASTER_DIR=D:\MASTER"

REM Persistent runtime DB/data
set "DATA_DIR=D:\FluentBitData"

REM Configuration
set "CONFIG_DIR=C:\ProgramData\FluentBit"
set "SERVICE_NAME=FluentBit"

echo.
echo ============================================================
echo Fluent Bit Windows OS Log Agent Installer v3
echo ============================================================
echo.

REM Administrator check
fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
    echo ERROR: Please run this CMD file as Administrator.
    pause
    exit /b 1
)

REM Detect metadata
set "HOST_NAME=%COMPUTERNAME%"
set "OS_NAME=windows"

echo Host detected: %HOST_NAME%
echo.

REM Environment
echo Select Environment:
echo 1. Prod
echo 2. Dmz
set /p ENV_CHOICE=Choice [1-2]:

if "%ENV_CHOICE%"=="1" (
    set "ENVIRONMENT=prod"
) else if "%ENV_CHOICE%"=="2" (
    set "ENVIRONMENT=dmz"
) else (
    goto BADINPUT
)

REM Server Role
echo.
echo Select Server Role:
echo 1. App
echo 2. Web
echo 3. Db
set /p ROLE_CHOICE=Choice [1-3]:

if "%ROLE_CHOICE%"=="1" (
    set "SERVER_ROLE=app"
) else if "%ROLE_CHOICE%"=="2" (
    set "SERVER_ROLE=web"
) else if "%ROLE_CHOICE%"=="3" (
    set "SERVER_ROLE=db"
) else (
    goto BADINPUT
)

REM Site
echo.
echo Select Site:
echo 1. Dc1
echo 2. Dc2
set /p SITE_CHOICE=Choice [1-2]:

if "%SITE_CHOICE%"=="1" (
    set "SITE=dc1"
) else if "%SITE_CHOICE%"=="2" (
    set "SITE=dc2"
) else (
    goto BADINPUT
)

REM App group
echo.
set /p APP_GROUP=Enter App Group:
if "%APP_GROUP%"=="" set "APP_GROUP=unknown"
set "APP_GROUP=%APP_GROUP: =_%"

REM Validate MASTER folder
if not exist "%MASTER_DIR%\" (
    echo ERROR: MASTER directory not found: %MASTER_DIR%
    pause
    exit /b 1
)

REM Create required directories
echo.
echo [1/7] Creating directories...
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%CONFIG_DIR%\conf.d" mkdir "%CONFIG_DIR%\conf.d"

REM Find Fluent Bit installer EXE directly in D:\MASTER
echo [2/7] Searching Fluent Bit package in %MASTER_DIR%...

set "INSTALLER="
for %%F in ("%MASTER_DIR%\fluent-bit*.exe") do (
    if exist "%%~fF" if not defined INSTALLER set "INSTALLER=%%~fF"
)

REM If filename is different, use first EXE except this installer script itself
if not defined INSTALLER (
    for %%F in ("%MASTER_DIR%\*.exe") do (
        if exist "%%~fF" if not defined INSTALLER set "INSTALLER=%%~fF"
    )
)

if not defined INSTALLER (
    echo ERROR: No Fluent Bit EXE found in:
    echo %MASTER_DIR%
    echo.
    echo Run this command to check files:
    echo dir "%MASTER_DIR%"
    pause
    exit /b 1
)

echo Fluent Bit package found:
echo %INSTALLER%

REM Run installer silently
echo.
echo [3/7] Installing Fluent Bit...
"%INSTALLER%" /S

REM Wait for installer
timeout /t 5 /nobreak >nul

REM Locate fluent-bit.exe after installation
set "FB_EXE="

if exist "C:\Program Files\Fluent Bit\bin\fluent-bit.exe" (
    set "FB_EXE=C:\Program Files\Fluent Bit\bin\fluent-bit.exe"
)

if not defined FB_EXE if exist "C:\Program Files\fluent-bit\bin\fluent-bit.exe" (
    set "FB_EXE=C:\Program Files\fluent-bit\bin\fluent-bit.exe"
)

if not defined FB_EXE if exist "C:\Program Files\FluentBit\bin\fluent-bit.exe" (
    set "FB_EXE=C:\Program Files\FluentBit\bin\fluent-bit.exe"
)

REM Search D:\MASTER recursively in case package is extracted there
if not defined FB_EXE (
    for /r "%MASTER_DIR%" %%F in (fluent-bit.exe) do (
        if not defined FB_EXE set "FB_EXE=%%~fF"
    )
)

if not defined FB_EXE (
    echo.
    echo ERROR: Installer completed but fluent-bit.exe was not found.
    echo.
    echo Please run:
    echo dir /s /b "C:\Program Files\fluent-bit.exe"
    echo.
    echo Or send me a screenshot after manually opening/running:
    echo %INSTALLER%
    pause
    exit /b 1
)

echo Fluent Bit executable:
echo %FB_EXE%

REM Main config
echo [4/7] Creating configuration...

(
echo [SERVICE]
echo     Flush        5
echo     Grace        30
echo     Log_Level    info
echo     Parsers_File parsers.conf
echo     storage.path D:/FluentBitData
echo     storage.sync normal
echo     storage.checksum off
echo     storage.backlog.mem_limit 50M
echo.
echo @INCLUDE conf.d\input-windows-eventlog.conf
echo @INCLUDE conf.d\filters.conf
echo @INCLUDE conf.d\output-loki.conf
) > "%CONFIG_DIR%\fluent-bit.conf"

REM Windows OS Event Logs only
(
echo # Windows OS Event Logs
echo # Security channel intentionally excluded
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.system
echo     Channels              System
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/system.db
echo     Read_Existing_Events  false
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.application
echo     Channels              Application
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/application.db
echo     Read_Existing_Events  false
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.setup
echo     Channels              Setup
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/setup.db
echo     Read_Existing_Events  false
) > "%CONFIG_DIR%\conf.d\input-windows-eventlog.conf"

REM Metadata
(
echo [FILTER]
echo     Name          record_modifier
echo     Match         os.windows.*
echo     Record        host %HOST_NAME%
echo     Record        os %OS_NAME%
echo     Record        environment %ENVIRONMENT%
echo     Record        app_group %APP_GROUP%
echo     Record        server_role %SERVER_ROLE%
echo     Record        site %SITE%
) > "%CONFIG_DIR%\conf.d\filters.conf"

REM Loki outputs
(
echo [OUTPUT]
echo     Name          loki
echo     Match         os.windows.system
echo     Host          %LOKI_HOST%
echo     Port          %LOKI_PORT%
echo     Uri           %LOKI_URI%
echo     Labels        job=os-logs,host=$host,os=$os,environment=$environment,app_group=$app_group,server_role=$server_role,site=$site,source=windows-system
echo     Line_Format   json
echo     Retry_Limit   False
echo.
echo [OUTPUT]
echo     Name          loki
echo     Match         os.windows.application
echo     Host          %LOKI_HOST%
echo     Port          %LOKI_PORT%
echo     Uri           %LOKI_URI%
echo     Labels        job=os-logs,host=$host,os=$os,environment=$environment,app_group=$app_group,server_role=$server_role,site=$site,source=windows-application
echo     Line_Format   json
echo     Retry_Limit   False
echo.
echo [OUTPUT]
echo     Name          loki
echo     Match         os.windows.setup
echo     Host          %LOKI_HOST%
echo     Port          %LOKI_PORT%
echo     Uri           %LOKI_URI%
echo     Labels        job=os-logs,host=$host,os=$os,environment=$environment,app_group=$app_group,server_role=$server_role,site=$site,source=windows-setup
echo     Line_Format   json
echo     Retry_Limit   False
) > "%CONFIG_DIR%\conf.d\output-loki.conf"

type nul > "%CONFIG_DIR%\parsers.conf"

REM Recreate service
echo [5/7] Creating Windows service...

sc query "%SERVICE_NAME%" >nul 2>&1
if "%errorlevel%"=="0" (
    sc stop "%SERVICE_NAME%" >nul 2>&1
    timeout /t 3 /nobreak >nul
    sc delete "%SERVICE_NAME%" >nul 2>&1
    timeout /t 2 /nobreak >nul
)

sc create "%SERVICE_NAME%" binPath= "\"%FB_EXE%\" -c \"%CONFIG_DIR%\fluent-bit.conf\"" start= auto DisplayName= "Fluent Bit OS Log Agent"

if not "%errorlevel%"=="0" (
    echo ERROR: Failed to create FluentBit service.
    pause
    exit /b 1
)

echo [6/7] Starting Fluent Bit...
sc start "%SERVICE_NAME%"

timeout /t 5 /nobreak >nul

echo [7/7] Checking service...
sc query "%SERVICE_NAME%"

echo.
echo ============================================================
echo INSTALLATION FINISHED
echo ============================================================
echo.
echo Host        : %HOST_NAME%
echo OS          : %OS_NAME%
echo Environment : %ENVIRONMENT%
echo App Group   : %APP_GROUP%
echo Server Role : %SERVER_ROLE%
echo Site        : %SITE%
echo.
echo Loki endpoint:
echo http://%LOKI_HOST%:%LOKI_PORT%%LOKI_URI%
echo.
echo Config:
echo %CONFIG_DIR%\fluent-bit.conf
echo.
echo Data:
echo %DATA_DIR%
echo.
echo Logs collected:
echo - System
echo - Application
echo - Setup
echo.
echo Security log is NOT collected.
echo.
pause
endlocal
exit /b 0

:BADINPUT
echo.
echo ERROR: Invalid selection.
pause
exit /b 1
