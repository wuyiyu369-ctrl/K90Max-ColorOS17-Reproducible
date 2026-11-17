@echo off
setlocal
if /i "%~1"=="devices" (
  if /i "%K90_MOCK_STATE%"=="adb" echo MOCKSERIAL	device
  if /i "%K90_MOCK_STATE%"=="multi" (
    echo MOCKSERIAL	device
    echo MOCKSERIAL2	device
  )
  exit /b 0
)
if /i "%~1"=="-s" (
  if /i "%~3"=="reboot" (
    >"%K90_MOCK_ROOT%\state.txt" echo bootloader
    exit /b 0
  )
  if /i "%~3"=="shell" (
    if /i "%~4"=="getprop" (
      if /i "%~5"=="ro.product.vendor.device" echo prague
      if /i "%~5"=="ro.product.odm.device" echo prague
      if /i "%~5"=="ro.build.version.release" echo 17
      exit /b 0
    )
    exit /b 0
  )
)
exit /b 0
