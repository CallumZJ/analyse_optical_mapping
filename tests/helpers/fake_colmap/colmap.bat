@echo off
rem Fake COLMAP for the sparse-model probes (probe_sparse_model_build)
rem Collin Snitchler
rem 14.10.2026
rem Stands in for colmap.exe so the "Build sparse model" steps can be
rem tested without COLMAP or a GPU. It understands only what the probes need:
rem   colmap help                  prints a COLMAP 4.2.1 (fake) banner
rem   colmap <command> -h          prints help_<command>.txt (copied from the
rem                                real COLMAP 4.2.1 help) or fails
rem   feature_extractor ...        creates the --database_path file
rem   exhaustive_matcher, rig_configurator   do nothing
rem   image_undistorter ... --output_path X  copies --image_path to X\images and
rem                                --input_path to X\sparse and makes X\stereo;
rem                                when X\images already holds files it fails
rem                                with exit code -1073740791 (0xC0000409), as
rem                                COLMAP 4.2.1 does when it re-runs into an
rem                                existing workspace
rem   image_deleter --input_path I --output_path X --image_names_path L
rem                                copies I to X and drops the images named in
rem                                L from X\images.txt (a text model; the real
rem                                COLMAP also drops the rest of a rig frame)
rem   mapper ... --output_path X   copies a model tree (a folder holding
rem                                0\, 1\, ...) into X: the first that exists of
rem                                %OM_FAKE_COLMAP_MODEL%\<parent of X>\<X name>,
rem                                %OM_FAKE_COLMAP_MODEL%\<parent of X>,
rem                                %OM_FAKE_COLMAP_MODEL%\<X name> and
rem                                %OM_FAKE_COLMAP_MODEL% (so a probe can give each
rem                                build and seed its own model, e.g.
rem                                orient_turn180\pass1_seed2)
rem Environment:
rem   OM_FAKE_COLMAP_MODEL    model tree the mapper "makes" (none = no model)
rem   OM_FAKE_COLMAP_EXIT     exit code of every command (default 0)
rem   OM_FAKE_COLMAP_FAIL_ON  command that exits with OM_FAKE_COLMAP_EXIT
rem                           (default: all commands)
rem   OM_FAKE_COLMAP_SLEEP    seconds each command waits (for cancel tests)
rem   OM_FAKE_COLMAP_LOG      file each command line is appended to
setlocal EnableExtensions
set "SUB=%~1"
if /i "%SUB%"=="help" (
    echo COLMAP 4.2.1 ^(fake^) -- Structure-from-Motion and Multi-View Stereo
    exit /b 0
)
if "%~2"=="-h" (
    if exist "%~dp0help_%SUB%.txt" (
        echo COLMAP 4.2.1 ^(fake^)
        type "%~dp0help_%SUB%.txt"
        exit /b 0
    )
    echo Unknown command %SUB%
    exit /b 1
)
if not "%OM_FAKE_COLMAP_LOG%"=="" echo %SUB% %* >> "%OM_FAKE_COLMAP_LOG%"
echo fake colmap %SUB%
set "DB="
set "OUT="
set "IMG="
set "INP="
set "LST="
shift
:args
if "%~1"=="" goto run
if "%~1"=="--database_path" set "DB=%~2"
if "%~1"=="--output_path" set "OUT=%~2"
if "%~1"=="--image_path" set "IMG=%~2"
if "%~1"=="--input_path" set "INP=%~2"
if "%~1"=="--image_names_path" set "LST=%~2"
shift
goto args
:run
if not "%OM_FAKE_COLMAP_SLEEP%"=="" ping -n %OM_FAKE_COLMAP_SLEEP% 127.0.0.1 >nul
set "CODE=0"
if not "%OM_FAKE_COLMAP_EXIT%"=="" (
    if "%OM_FAKE_COLMAP_FAIL_ON%"=="" set "CODE=%OM_FAKE_COLMAP_EXIT%"
    if /i "%OM_FAKE_COLMAP_FAIL_ON%"=="%SUB%" set "CODE=%OM_FAKE_COLMAP_EXIT%"
)
if not "%CODE%"=="0" (
    echo fake colmap %SUB% fails with exit code %CODE%
    exit /b %CODE%
)
if /i "%SUB%"=="feature_extractor" (
    if not "%DB%"=="" if not exist "%DB%" type nul > "%DB%"
)
if /i "%SUB%"=="image_undistorter" goto undistort
if /i "%SUB%"=="image_deleter" goto imdel
if /i not "%SUB%"=="mapper" exit /b 0
if "%OM_FAKE_COLMAP_MODEL%"=="" exit /b 0
if "%OUT%"=="" exit /b 0
for %%I in ("%OUT%") do set "LEAF=%%~nxI"
for %%I in ("%OUT%\..") do set "UP=%%~fI"
for %%I in ("%UP%") do set "PARENT=%%~nxI"
set "SRC=%OM_FAKE_COLMAP_MODEL%"
if exist "%OM_FAKE_COLMAP_MODEL%\%LEAF%\" set "SRC=%OM_FAKE_COLMAP_MODEL%\%LEAF%"
if exist "%OM_FAKE_COLMAP_MODEL%\%PARENT%\" set "SRC=%OM_FAKE_COLMAP_MODEL%\%PARENT%"
if exist "%OM_FAKE_COLMAP_MODEL%\%PARENT%\%LEAF%\" set "SRC=%OM_FAKE_COLMAP_MODEL%\%PARENT%\%LEAF%"
xcopy /e /i /y /q "%SRC%" "%OUT%" >nul
exit /b 0
:undistort
if "%OUT%"=="" exit /b 0
if exist "%OUT%\images\" (
    dir /s /b /a-d "%OUT%\images" 2>nul | findstr /r "." >nul && (
        echo Copying already undistorted image to an existing file: crash
        exit /b -1073740791
    )
)
if not "%IMG%"=="" xcopy /e /i /y /q "%IMG%" "%OUT%\images" >nul
if not "%INP%"=="" xcopy /e /i /y /q "%INP%" "%OUT%\sparse" >nul
if not exist "%OUT%\stereo\" mkdir "%OUT%\stereo"
exit /b 0
:imdel
if "%OUT%"=="" exit /b 0
if "%INP%"=="" exit /b 0
xcopy /e /i /y /q "%INP%" "%OUT%" >nul
set "FAKE_LIST=%LST%"
set "FAKE_OUT=%OUT%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$n = @(Get-Content -LiteralPath $env:FAKE_LIST | Where-Object { $_ -ne '' }); $f = Join-Path $env:FAKE_OUT 'images.txt'; $l = @(Get-Content -LiteralPath $f); $o = New-Object System.Collections.Generic.List[string]; $i = 0; while ($i -lt $l.Count) { $s = $l[$i]; if ($s.StartsWith('#')) { $o.Add($s); $i++; continue }; $p = $s -split ' '; if ($p.Count -ge 10 -and $n -contains $p[9]) { $i += 2; continue }; $o.Add($s); if ($i + 1 -lt $l.Count) { $o.Add($l[$i + 1]) }; $i += 2 }; [IO.File]::WriteAllLines($f, $o)"
exit /b %errorlevel%
