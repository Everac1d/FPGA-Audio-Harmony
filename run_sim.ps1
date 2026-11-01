param([string[]]$Cases=@(),[string]$Python='python.exe',[string]$IcarusBin=([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\tools\icarus\ucrt64\bin'))))
$ErrorActionPreference='Stop'
$taskDrive=$null
foreach($candidate in @('Z:','Y:','X:','W:')){if(!(Test-Path -LiteralPath ($candidate+'\'))){$taskDrive=$candidate;break}}
if(!$taskDrive){throw 'No free temporary drive'}
& subst.exe $taskDrive $PSScriptRoot
if($LASTEXITCODE -ne 0){throw 'Temporary mapping failed'}
try {
  & $Python -X utf8 ($taskDrive+'\sim\run.py') --icarus $IcarusBin @Cases
  if($LASTEXITCODE -ne 0){throw 'Simulation failed'}
} finally {& subst.exe $taskDrive /D}
