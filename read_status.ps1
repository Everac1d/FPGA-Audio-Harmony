param(
    [string]$PortName = 'COM7',
    [int]$Seconds = 12,
    [int]$WarmupSeconds = 2,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
if ($Seconds -lt 1 -or $Seconds -gt 900) { throw 'Seconds must be 1..900.' }
if ($WarmupSeconds -lt 0 -or $WarmupSeconds -gt 5) { throw 'WarmupSeconds must be 0..5.' }


# Pure packet filter, deliberately separated so offline tests never execute
# SerialPort construction/Open or capture-file code below.
function Test-StatusLine {
    param([string]$Line)
    $Line=$Line.TrimEnd([char[]]"`r`n")
    $signed5='(?:0[0-9A-C]|1[4-9A-F])'
    $failure='^D3 V=(?:00032503|00032601|00032701|00032901|00033001|00033002|00033003|00033101|00033102|00033103|00033104|00033105|00033106|00033107|00033109) J=[0-9A-F] B=[01][0-9A-F]{7} W=[0-9A-F]{64} R=[0-9A-F]{64}$'
    if(($Line -cmatch $failure) -and $Line.Length -eq 162){return $true}
    $body=' S=[01] M=[0-2] A=[0-2] N='+$signed5+' H=[02456] T=[0-9A] L=[01][0-9A-F]{5} P=[01][0-9A-F]{5} D=[01] E=[01] F=[01] I=[01] U=[0-9A-F]{8} O=[0-9A-F]{8}'
    $legacyShort=($Line -cmatch ('^R3 V=00032501'+$body+'$')) -and $Line.Length -eq 94
    $legacy=($Line -cmatch ('^R3 V=(?:00032502|00032503|00032601|00032701|00032901|00033001)'+$body+' X=[0-9A-F]{4}$')) -and $Line.Length -eq 101
    $fineBody=' S=[01] M=[0-2] A=[0-2] N='+$signed5+' H=(?:0[A-F]|1[0-9A-E]) T=[0-9AB] L=[01][0-9A-F]{5} P=[01][0-9A-F]{5} D=[01] E=[01] F=[01] I=[01] U=[0-9A-F]{8} O=[0-9A-F]{8} X=[0-9A-F]{4}'
    $fine=($Line -cmatch ('^R4 V=(?:00033002|00033003|00033101|00033102|00033103)'+$fineBody+'$')) -and $Line.Length -eq 102
    $dualBody=$fineBody.Replace('A=[0-2]','A=[0-3]')
    $voices=' Q='+$signed5+' C=[01]'
    $dual=($Line -cmatch ('^R5 V=00033104'+$dualBody+$voices+'$')) -and $Line.Length -eq 111
    $longBody=$fineBody.Replace('L=[01][0-9A-F]{5} P=[01][0-9A-F]{5}','L=[0-9A-F]{8} P=[0-9A-F]{8}')
    $long=($Line -cmatch ('^R6 V=(?:00033105|00033106|00033107|00033109)'+$longBody+$voices+'$')) -and $Line.Length -eq 115
    if(-not ($legacyShort -or $legacy -or $fine -or $dual -or $long)){return $false}
    $counts=[regex]::Match($Line,' L=(?<record>[0-9A-F]+) P=(?<play>[0-9A-F]+) ')
    if(-not $counts.Success){return $false}
    $limit=1464844
    if($long){$limit=14648438}
    return ([Convert]::ToUInt32($counts.Groups['record'].Value,16) -le $limit) -and
        ([Convert]::ToUInt32($counts.Groups['play'].Value,16) -le $limit)
}

# 只有用户主动执行此脚本才会打开串口。DTR/RTS 关闭，避免影响板上复位。
# Windows PowerShell 5.1的串口类型已在System.dll中；PowerShell 7按需加载独立程序集。
if (-not ('System.IO.Ports.SerialPort' -as [type])) {
    Add-Type -AssemblyName System.IO.Ports
}
$statusPort = [System.IO.Ports.SerialPort]::new($PortName, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$statusPort.Handshake = [System.IO.Ports.Handshake]::None
$statusPort.DtrEnable = $false
$statusPort.RtsEnable = $false
$statusPort.ReadTimeout = 400
$statusPort.NewLine = "`n"
$captureText = [System.Text.StringBuilder]::new()
$resultsDirectory = Join-Path $PSScriptRoot 'hardware_results'
[void][System.IO.Directory]::CreateDirectory($resultsDirectory)
$capturePath = Join-Path $resultsDirectory ('uart_status_{0}.log' -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$opened = $false
$timer = $null
$captureStart = $null
$captureWriter = $null
try {
    $statusPort.Open()
    $opened = $true
    # 丢弃主机先前积累的数据，时间戳对应本次采集窗口。
    $statusPort.DiscardInBuffer()
    # 部分USB桥接器在Open后继续交付设备侧旧队列；短暂持续读取并丢弃。
    # 主机接收时间仍不代表FPGA快照的精确采样时刻。
    $warmupTimer = [Diagnostics.Stopwatch]::StartNew()
    while ($warmupTimer.Elapsed.TotalSeconds -lt $WarmupSeconds) {
        [void]$statusPort.ReadExisting()
        [Threading.Thread]::Sleep(20)
    }
    $statusPort.DiscardInBuffer()
    $captureStart = Get-Date
    # 实时落盘，长时间测试时可以读取进度，进程意外中止也能保留已收快照。
    $captureWriter = [IO.StreamWriter]::new($capturePath, $false, [Text.UTF8Encoding]::new($true))
    $captureWriter.AutoFlush = $true
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        try {
            $line = $statusPort.ReadLine().TrimEnd("`r")
            # Open时可能恰逢报文中间，仅保存完整且范围合法的快照。
            if (Test-StatusLine -Line $line) {
                $timedLine = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $line
                [void]$captureText.AppendLine($timedLine)
                $captureWriter.WriteLine($timedLine)
                if (!$Quiet) { Write-Output $timedLine }
            }
        } catch [System.TimeoutException] { }
    }
} finally {
    if ($statusPort.IsOpen) { $statusPort.Close() }
    $statusPort.Dispose()
    if ($opened) {
        if ($null -ne $captureWriter) { $captureWriter.Dispose() }
        else { $captureText.ToString() | Set-Content -LiteralPath $capturePath -Encoding utf8 }
        if ($null -ne $timer) {
            [ordered]@{
                AcceptedR3LengthWithCRLF=@(96,103);AcceptedR4LengthWithCRLF=104;AcceptedR5LengthWithCRLF=113;AcceptedR6LengthWithCRLF=117;D3LengthWithCRLF=164;UserCodes=@('0x00032501','0x00032502','0x00032503','0x00032701','0x00032601','0x00032901','0x00033001','0x00033002','0x00033003','0x00033101','0x00033102','0x00033103','0x00033104','0x00033105','0x00033106','0x00033107','0x00033109');Fields='S source 0 live 1 clip; M actual monitor; A effect; N signed5 semitone raw; H legacy gain0/2/4/5/6 or R4/R5/R6 tenths0A..1E; R5/R6 Q signed5 second pitch; C editor voice0/1; T recorder state0..B (B paused); L sample progress committed except T2/T3; P raw playback position; R6 L/P are32bit8hex limited14648438; D DDR selftest-ready; E storage fault; F full; I microphone ready; U/O output queue under/overflow; X diagnostic code[15:12], bridge state[11:8], memory status[7:0]; D3 J first failed test index; B app word address; W expected256; R actual256';
                Port=$PortName;Baud=115200;StartHostTime=$captureStart.ToString('o');
                EndHostTime=(Get-Date).ToString('o');ElapsedSeconds=$timer.Elapsed.TotalSeconds;
                RequestedSeconds=$Seconds;WarmupSeconds=$WarmupSeconds;Log=$capturePath;
                TimestampMeaning='Host receive time; not an exact FPGA sample clock measurement'
            } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath ($capturePath + '.meta.json') -Encoding utf8
        }
        Write-Output ('Saved: {0}' -f $capturePath)
        if ($captureText.Length -eq 0) { Write-Warning 'No complete R3/R4/R5/R6 or D3 line received during this capture.' }
    }
}
