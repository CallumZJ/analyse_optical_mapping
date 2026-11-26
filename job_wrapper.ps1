# Job wrapper of the Reconstruction tab (Windows only)
# Collin Snitchler
# 09.09.2026
# The tab starts COLMAP, APDe-MVS and Python through this wrapper on Windows
# (rabbit_reconstruction_tab). Sources: Microsoft Win32 Job Objects
# (CreateJobObject, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE).
#
# It runs a command inside a Windows Job Object with
# KILL_ON_JOB_CLOSE (the whole child tree dies if this wrapper dies) and
# polls a cancel file (when present, the job is terminated as a unit).
#
# Exit codes: 0 = child exited 0; N = child exited N; 130 = cancelled via
# cancel file; 90-92 = setup failure.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File job_wrapper.ps1 `
#       -JobName <name> -Command <cmdline> -PidFile <pidfile> -CancelFile <cancel>
param(
    [string]$JobName = 'rec_job',
    [string]$Command = '',
    [string]$PidFile = '',
    [string]$CancelFile = ''
)
# Any error that stops this script is said on its output, which the app
# keeps in <stage>_wrapper.log (exit 93)
trap { Write-Output "job_wrapper failed: $($_.Exception.Message)"; exit 93 }
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class JobWrap {
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
    public Int64 PerProcessUserTimeLimit;
    public Int64 PerJobUserTimeLimit;
    public UInt32 LimitFlags;
    public UIntPtr MinimumWorkingSetSize;
    public UIntPtr MaximumWorkingSetSize;
    public UInt32 ActiveProcessLimit;
    public IntPtr Affinity;
    public UInt32 PriorityClass;
    public UInt32 SchedulingClass;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct IO_COUNTERS {
    public UInt64 ReadOperationCount;
    public UInt64 WriteOperationCount;
    public UInt64 OtherOperationCount;
    public UInt64 ReadTransferCount;
    public UInt64 WriteTransferCount;
    public UInt64 OtherTransferCount;
  }
  [StructLayout(LayoutKind.Sequential)]
  public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
    public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
    public IO_COUNTERS IoInfo;
    public UIntPtr ProcessMemoryLimit;
    public UIntPtr JobMemoryLimit;
    public UIntPtr PeakProcessMemoryUsed;
    public UIntPtr PeakJobMemoryUsed;
  }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr CreateJobObject(IntPtr a, string name);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool TerminateJobObject(IntPtr hJob, uint code);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool SetInformationJobObject(IntPtr hJob, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, int infoLength);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
}
"@
$job = [JobWrap]::CreateJobObject([IntPtr]::Zero, $JobName)
if ($job -eq [IntPtr]::Zero) { Write-Error "CreateJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 90 }
# KILL_ON_JOB_CLOSE (0x2000): if this wrapper dies, the whole tree dies.
$info = New-Object JobWrap+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
$info.BasicLimitInformation.LimitFlags = 0x2000
$ok = [JobWrap]::SetInformationJobObject($job, 9, [ref]$info, [Runtime.InteropServices.Marshal]::SizeOf($info))
if (-not $ok) { Write-Error "SetInformationJobObject failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 90 }
$p = Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', "`"$Command`"" -PassThru -WindowStyle Hidden
if (-not $p) { Write-Error "Start-Process failed"; exit 91 }
$ok = [JobWrap]::AssignProcessToJobObject($job, $p.Handle)
if (-not $ok) { Write-Error "Assign failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())"; exit 92 }
if ($PidFile) {
    try { Set-Content -Path $PidFile -Value $p.Id -ErrorAction Stop }
    catch { Write-Output "job_wrapper: could not write $PidFile ($($_.Exception.Message)); the stage runs on" }
}
$code = 0
while ($true) {
    if ($CancelFile -and (Test-Path -Path $CancelFile)) {
        [JobWrap]::TerminateJobObject($job, 1) | Out-Null
        $code = 130
        break
    }
    if ($p.HasExited) {
        $code = $p.ExitCode
        break
    }
    Start-Sleep -Milliseconds 200
}
[JobWrap]::CloseHandle($job) | Out-Null
exit $code
