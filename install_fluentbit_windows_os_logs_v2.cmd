@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Fluent Bit Windows OS Log Agent - CMD only

set "LOKI_HOST=192.168.114.75"
set "LOKI_PORT=80"
set "LOKI_URI=/loki/api/v1/push"
set "MASTER_DIR=D:\MASTER\fluent-bit-5.1.1-win64"
set "DATA_DIR=D:\FluentBitData"
set "CONFIG_DIR=C:\ProgramData\FluentBit"
set "SERVICE_NAME=FluentBit"

set "HOST_NAME=%COMPUTERNAME%"
set "OS_NAME=windows"

echo ==========================================
echo Fluent Bit Windows OS Log Agent Installer v2
echo ==========================================
echo Host detected: %HOST_NAME%
echo.

echo Select Environment:
echo 1. Prod
echo 2. Dmz
set /p ENV_CHOICE=Choice [1-2]:
if "%ENV_CHOICE%"=="1" set "ENVIRONMENT=prod"
if "%ENV_CHOICE%"=="2" set "ENVIRONMENT=dmz"
if not defined ENVIRONMENT goto :BADINPUT

echo Select Server Role:
echo 1. App
echo 2. Web
echo 3. Db
set /p ROLE_CHOICE=Choice [1-3]:
if "%ROLE_CHOICE%"=="1" set "SERVER_ROLE=app"
if "%ROLE_CHOICE%"=="2" set "SERVER_ROLE=web"
if "%ROLE_CHOICE%"=="3" set "SERVER_ROLE=db"
if not defined SERVER_ROLE goto :BADINPUT

echo Select Site:
echo 1. Dc1
echo 2. Dc2
set /p SITE_CHOICE=Choice [1-2]:
if "%SITE_CHOICE%"=="1" set "SITE=dc1"
if "%SITE_CHOICE%"=="2" set "SITE=dc2"
if not defined SITE goto :BADINPUT

set /p APP_GROUP=Enter App Group:
if "%APP_GROUP%"=="" set "APP_GROUP=unknown"
set "APP_GROUP=%APP_GROUP: =_%"

REM Administrator / elevated CMD check.
REM "net session" is not reliable on servers because it can fail when
REM the Server service is disabled even when CMD is elevated.
fltmc >nul 2>&1
if not "%errorlevel%"=="0" (
 echo.
 echo ERROR: This CMD window is not elevated.
 echo Please start Command Prompt using "Run as administrator".
 echo.
 echo If you are sure CMD is elevated, run:
 echo   whoami /groups
 echo and send me the output.
 pause
 exit /b 1
)

if not exist "%MASTER_DIR%" (
 echo ERROR: Folder not found: %MASTER_DIR%
 pause
 exit /b 1
)

if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%CONFIG_DIR%\conf.d" mkdir "%CONFIG_DIR%\conf.d"

REM Locate already extracted Fluent Bit first
set "FB_EXE="
for /r "%MASTER_DIR%" %%F in (fluent-bit.exe) do if not defined FB_EXE set "FB_EXE=%%~fF"

REM If not extracted, run first EXE in MASTER_DIR silently
if not defined FB_EXE (
 set "INSTALLER="
 for %%F in ("%MASTER_DIR%\*.exe") do if not defined INSTALLER set "INSTALLER=%%~fF"
 if not defined INSTALLER (
  echo ERROR: No installer EXE found in %MASTER_DIR%
  pause
  exit /b 1
 )
 echo Running installer: %INSTALLER%
 "%INSTALLER%" /S
)

REM Search common installed locations
if not defined FB_EXE if exist "C:\Program Files\Fluent Bit\bin\fluent-bit.exe" set "FB_EXE=C:\Program Files\Fluent Bit\bin\fluent-bit.exe"
if not defined FB_EXE if exist "C:\Program Files\fluent-bit\bin\fluent-bit.exe" set "FB_EXE=C:\Program Files\fluent-bit\bin\fluent-bit.exe"
if not defined FB_EXE if exist "C:\Program Files\FluentBit\bin\fluent-bit.exe" set "FB_EXE=C:\Program Files\FluentBit\bin\fluent-bit.exe"

if not defined FB_EXE (
 echo ERROR: fluent-bit.exe not found after installation.
 echo Send me the exact installer filename if this occurs.
 pause
 exit /b 1
)

echo Using Fluent Bit: %FB_EXE%

REM Main configuration
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

REM OS-only Windows Event Logs. Security intentionally excluded.
(
echo # Windows OS logs only - Security is NOT collected
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.system
echo     Channels              System
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/system.db
echo     Read_Existing_Events  true
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.application
echo     Channels              Application
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/application.db
echo     Read_Existing_Events  true
echo.
echo [INPUT]
echo     Name                  winlog
echo     Tag                   os.windows.setup
echo     Channels              Setup
echo     Interval_Sec          1
echo     DB                    D:/FluentBitData/setup.db
echo     Read_Existing_Events  true
) > "%CONFIG_DIR%\conf.d\input-windows-eventlog.conf"

REM Common labels
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

REM Loki output. Source differs by Windows channel.
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

REM Empty parser file is enough because this configuration does not parse text files.
if not exist "%CONFIG_DIR%\parsers.conf" type nul > "%CONFIG_DIR%\parsers.conf"

REM Recreate service with explicit configuration
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

sc start "%SERVICE_NAME%"
timeout /t 5 /nobreak >nul

echo.
echo ==========================================
echo INSTALLATION COMPLETE
echo ==========================================
echo Host        : %HOST_NAME%
echo OS          : %OS_NAME%
echo Environment : %ENVIRONMENT%
echo Site        : %SITE%
echo App Group   : %APP_GROUP%
echo Server Role : %SERVER_ROLE%
echo.
echo Loki endpoint:
echo http://%LOKI_HOST%:%LOKI_PORT%%LOKI_URI%
echo.
echo Config: %CONFIG_DIR%\fluent-bit.conf
echo Data:   %DATA_DIR%
echo.
echo Collected: System, Application, Setup
echo Excluded : Security
echo.
echo Check service: sc query FluentBit
pause
endlocal
exit /b 0

:BADINPUT
echo Invalid selection.
pause
exit /b 1
