@echo off
setlocal EnableExtensions DisableDelayedExpansion

cd /d "%~dp0"
if errorlevel 1 exit /b 1

set "PRIVATE_ROOT="
set "PRIVATE_IMPL="
set "PRIVATE_BINDING="
set "TARGET_DIR=%CD%\lib\services\quick_import"
set "TARGET_IMPL=%TARGET_DIR%\local_quick_import_backend.dart"
set "TARGET_BINDING=%TARGET_DIR%\backend_binding.dart"
set "API_BINDING=%TARGET_DIR%\backend_binding.api.dart"
set "SYMBOL_DIR=%CD%\private-symbol-output"
set "BUILD_KIND=apk"
set "INJECTED_PRIVATE=0"
set "RESULT=1"

if /i "%~1"=="appbundle" set "BUILD_KIND=appbundle"
if /i "%~1"=="aab" set "BUILD_KIND=appbundle"
if not "%~1"=="" if /i not "%~1"=="apk" if /i not "%~1"=="appbundle" if /i not "%~1"=="aab" (
  echo Usage: build.bat [apk^|appbundle]
  exit /b 64
)

if not exist "%API_BINDING%" (
  echo [ERROR] Missing public API binding template: "%API_BINDING%"
  exit /b 2
)

if not defined QUICK_IMPORT_DISABLE_PRIVATE (
  if defined QUICK_IMPORT_PRIVATE_SOURCE call :try_private_root "%QUICK_IMPORT_PRIVATE_SOURCE%"
  if not defined PRIVATE_ROOT call :try_private_root "%CD%\..\callrool-app-inner"
  if not defined PRIVATE_ROOT call :try_private_root "%CD%\.official-private"
  if not defined PRIVATE_ROOT call :try_private_root "%CD%\temp\private-quick-import"
)

if defined PRIVATE_ROOT (
  echo [INFO] Private quick-import source found: "%PRIVATE_ROOT%"
  copy /y "%PRIVATE_IMPL%" "%TARGET_IMPL%" >nul || goto :cleanup
  copy /y "%PRIVATE_BINDING%" "%TARGET_BINDING%" >nul || goto :cleanup
  set "INJECTED_PRIVATE=1"
  echo [INFO] Building with LocalQuickImportBackend.
) else (
  copy /y "%API_BINDING%" "%TARGET_BINDING%" >nul || goto :cleanup
  if exist "%TARGET_IMPL%" del /f /q "%TARGET_IMPL%" >nul 2>&1
  echo [INFO] No complete private source found. Falling back to ApiQuickImportBackend.
)

call flutter pub get
if errorlevel 1 goto :cleanup

call flutter analyze
if errorlevel 1 goto :cleanup

call flutter test
if errorlevel 1 goto :cleanup

if not exist "%SYMBOL_DIR%" mkdir "%SYMBOL_DIR%"
if errorlevel 1 goto :cleanup

if /i "%BUILD_KIND%"=="appbundle" (
  call flutter build appbundle --release --obfuscate --split-debug-info="%SYMBOL_DIR%" --target-platform android-arm64 --split-per-abi
) else (
  call flutter build apk --release --obfuscate --split-debug-info="%SYMBOL_DIR%" --target-platform android-arm64 --split-per-abi
)
if errorlevel 1 goto :cleanup

set "RESULT=0"

:cleanup
copy /y "%API_BINDING%" "%TARGET_BINDING%" >nul 2>&1
if exist "%TARGET_IMPL%" del /f /q "%TARGET_IMPL%" >nul 2>&1

if "%RESULT%"=="0" (
  echo [OK] %BUILD_KIND% release build completed.
  echo [OK] Obfuscation symbols retained in "%SYMBOL_DIR%".
  if "%INJECTED_PRIVATE%"=="1" echo [OK] Private source was removed and the API binding was restored.
) else (
  echo [ERROR] Build failed. Public API binding has been restored.
)

exit /b %RESULT%

:try_private_root
set "CANDIDATE_ROOT=%~f1"
set "CANDIDATE_IMPL=%CANDIDATE_ROOT%\lib\services\quick_import\local_quick_import_backend.dart"
set "CANDIDATE_BINDING=%CANDIDATE_ROOT%\lib\services\quick_import\backend_binding.dart"
if exist "%CANDIDATE_IMPL%" if exist "%CANDIDATE_BINDING%" (
  set "PRIVATE_ROOT=%CANDIDATE_ROOT%"
  set "PRIVATE_IMPL=%CANDIDATE_IMPL%"
  set "PRIVATE_BINDING=%CANDIDATE_BINDING%"
)
exit /b 0
