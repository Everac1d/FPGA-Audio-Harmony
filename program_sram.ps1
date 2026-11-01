param(
    [string]$Programmer = 'D:\Gowin\Gowin_V1.9.12.04_x64\Programmer\bin\programmer_cli.exe',
    [int]$CableIndex = 1
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath($PSScriptRoot)
if (!(Test-Path -LiteralPath $Programmer -PathType Leaf)) { throw 'Programmer missing; supply -Programmer.' }
$infoPath = Join-Path $projectRoot 'ready_to_program\BUILD_INFO.json'
$info = Get-Content -LiteralPath $infoPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bitstream = Join-Path $projectRoot ('ready_to_program\' + $info.File)
if ((Get-FileHash -LiteralPath $bitstream -Algorithm SHA256).Hash -ne $info.SHA256) { throw 'Bitstream hash mismatch.' }
foreach ($property in $info.SourceHashes.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $property.Name) -Algorithm SHA256).Hash -ne $property.Value) {
        throw ('Source changed; rebuild before programming: ' + $property.Name)
    }
}
$header = Get-Content -LiteralPath $bitstream -TotalCount 32
if (!($header -match '^//Device Version: B$') -or !($header -match '^//Compress: ON$')) { throw 'Expected compressed B-version bitstream.' }
$ErrorActionPreference = 'Continue'
try {
    $scan = @(& $Programmer --scan --cable-index $CableIndex --channel 0 --frequency 2.5MHz 2>&1) | ForEach-Object { [string]$_ }
    $scanExit = $LASTEXITCODE
} finally { $ErrorActionPreference = 'Stop' }
$scan | Tee-Object -FilePath (Join-Path $projectRoot 'jtag_scan.log')
if ($scanExit -ne 0 -or !($scan -match '^\s*1 device\(s\) found!') -or !($scan -match '0x0001081B')) {
    throw 'Expected one connected device; inspect jtag_scan.log. No programming attempted.'
}
$mappedDrive = $null
foreach ($candidate in @('Z:','Y:','X:','W:')) {
    if (!(Test-Path -LiteralPath ($candidate + '\'))) { $mappedDrive = $candidate; break }
}
if (!$mappedDrive) { throw 'No free temporary drive.' }
& subst.exe $mappedDrive $projectRoot
if ($LASTEXITCODE -ne 0) { throw 'Temporary drive mapping failed.' }
try {
    # operation_index 2只写SRAM；本脚本不写Flash或OTP。
    $ErrorActionPreference = 'Continue'
    try {
        $lines = @(& $Programmer --device GW5AST-138B --operation_index 2 --cable-index $CableIndex --channel 0 --frequency 2.5MHz --fsFile ($mappedDrive + '/ready_to_program/' + $info.File) 2>&1) | ForEach-Object { [string]$_ }
        $programExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = 'Stop' }
    $lines | Tee-Object -FilePath (Join-Path $projectRoot 'program_record_ddr_sram.log')
    $match = $lines -match ('(?i)^\s*User Code is:\s*' + [regex]::Escape($info.UserCode) + '\s*$')
    if ($programExit -ne 0 -or !($lines -match '^\s*Finished\.\s*$') -or !$match) { throw 'SRAM programming or user-code verification failed.' }
} finally {
    & subst.exe $mappedDrive /D
}
