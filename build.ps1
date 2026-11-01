param([ValidateSet('compile','finalize','build')][string]$Action='build',
  [string]$Python='python.exe',
  [string]$GowinShell='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe')
$ErrorActionPreference='Stop';$taskDrive=$null
foreach($candidate in @('Z:','Y:','X:','W:')){if(!(Test-Path -LiteralPath ($candidate+'\'))){$taskDrive=$candidate;break}}
if(!$taskDrive){throw 'No free temporary drive'}
& subst.exe $taskDrive $PSScriptRoot
if($LASTEXITCODE -ne 0){throw 'Temporary mapping failed'}
try {
 & $Python -X utf8 ($taskDrive+'\build_project.py') $Action --gowin $GowinShell
 if($LASTEXITCODE -ne 0){throw 'Build validation failed'}
} finally {& subst.exe $taskDrive /D}
