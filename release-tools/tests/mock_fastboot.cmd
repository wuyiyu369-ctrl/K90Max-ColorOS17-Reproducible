@echo off
setlocal EnableExtensions
set "STATE=%K90_MOCK_STATE%"
if exist "%K90_MOCK_ROOT%\state.txt" set /p STATE=<"%K90_MOCK_ROOT%\state.txt"
if /i "%~1"=="devices" (
  if /i "%STATE%"=="bootloader" echo MOCKSERIAL	fastboot
  if /i "%STATE%"=="fastbootd" echo MOCKSERIAL	fastboot
  if /i "%STATE%"=="multi" (
    echo MOCKSERIAL	fastboot
    echo MOCKSERIAL2	fastboot
  )
  exit /b 0
)
if /i "%~1"=="-s" (
  if /i "%~3"=="getvar" (
    if /i "%~4"=="product" 1>&2 echo product: prague
    if /i "%~4"=="unlocked" 1>&2 echo unlocked: yes
    if /i "%~4"=="is-userspace" (
      if /i "%STATE%"=="fastbootd" (1>&2 echo is-userspace: yes) else (1>&2 echo is-userspace: no)
    )
    exit /b 0
  )
  if /i "%~3"=="reboot" (
    if /i "%~4"=="fastboot" (
      >"%K90_MOCK_ROOT%\state.txt" echo fastbootd
    ) else if /i "%~4"=="bootloader" (
      >"%K90_MOCK_ROOT%\state.txt" echo bootloader
    )
    exit /b 0
  )
  if /i "%~3"=="flash" (
    if /i "%K90_MOCK_FAIL_PART%"=="%~4" (
      echo MOCK_FAIL %~4
      exit /b 1
    )
    if /i "%~4"=="super" (
      1>&2 echo Sending sparse 'super' 1/3
      1>&2 echo Sending sparse 'super' 2/3
      1>&2 echo Sending sparse 'super' 3/3
    )
    echo OKAY %~4
    exit /b 0
  )
  if /i "%~3"=="-w" (
    if /i "%K90_MOCK_FAIL_WIPE%"=="1" (echo MOCK_FAIL wipe& exit /b 1)
    echo OKAY wipe
    exit /b 0
  )
)
exit /b 0
