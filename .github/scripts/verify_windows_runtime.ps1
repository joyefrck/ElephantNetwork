param(
  [Parameter(Mandatory)][string]$InstallDirectory,
  [Parameter(Mandatory)][string]$Receipt
)

$ErrorActionPreference = 'Stop'
$checks = [ordered]@{}
$sessionId = [guid]::NewGuid().ToString('N')
$pipeName = "ElephantNetworkCore_$sessionId"
$pipe = [IO.Pipes.NamedPipeServerStream]::new($pipeName, [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
$runtimeHome = Join-Path $env:RUNNER_TEMP "elephant-runtime-$sessionId"
New-Item -ItemType Directory -Path $runtimeHome -Force | Out-Null
$serverScript = Join-Path $runtimeHome 'http_server.py'
@'
import http.server
import pathlib
import sys
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def do_HEAD(self):
        if self.path == '/slow':
            time.sleep(0.4)
        self.send_response(204)
        self.end_headers()
    def do_GET(self):
        self.send_response(204)
        self.end_headers()
    def log_message(self, *args):
        pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
pathlib.Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()
'@ | Set-Content $serverScript -Encoding utf8
$portFile = Join-Path $runtimeHome 'http-port'
$httpServer = Start-Process python -ArgumentList @("`"$serverScript`"", "`"$portFile`"") -RedirectStandardError (Join-Path $runtimeHome 'http.stderr.log') -PassThru
$script:requestId = 0
$script:spilledResponses = 0

function Read-CoreBytes([int]$Length) {
  $buffer = [byte[]]::new($Length)
  $offset = 0
  while ($offset -lt $Length) {
    $read = $pipe.ReadAsync($buffer, $offset, $Length - $offset)
    if (!$read.Wait(15000)) { throw 'Core response timed out' }
    if ($read.Result -eq 0) { throw 'Core disconnected' }
    $offset += $read.Result
  }
  return ,$buffer
}

function Invoke-Core([string]$Method, $Arguments = $null, [string]$ExpectedError = '') {
  $script:requestId++
  $id = [string]$script:requestId
  $payload = [Text.Encoding]::UTF8.GetBytes((@{ id = $id; method = $Method; arguments = $Arguments } | ConvertTo-Json -Depth 100 -Compress))
  $prefix = [BitConverter]::GetBytes([uint32]$payload.Length)
  $pipe.Write($prefix, 0, $prefix.Length)
  $pipe.Write($payload, 0, $payload.Length)
  $pipe.Flush()
  while ($true) {
    $length = [BitConverter]::ToUInt32((Read-CoreBytes 4), 0)
    if ($length -gt 67108864) { throw 'Oversized Core frame' }
    $response = [Text.Encoding]::UTF8.GetString((Read-CoreBytes $length)) | ConvertFrom-Json -Depth 100
    if ($response.id -ne $id) { continue }
    if ($response.file) {
      $expectedDirectory = Join-Path $runtimeHome 'responses'
      if ([IO.Path]::GetDirectoryName($response.file) -ne $expectedDirectory) { throw 'Unexpected response file directory' }
      $responsePath = $response.file
      if ((Get-Item $responsePath).Length -le 1048576) { throw 'Large response did not exceed 1 MiB' }
      $response = Get-Content $responsePath -Raw | ConvertFrom-Json -Depth 100
      Remove-Item $responsePath
      $script:spilledResponses++
      if ($response.id -ne $id) { throw 'Spilled response ID mismatch' }
    }
    if ($ExpectedError) {
      if ($response.error.code -ne $ExpectedError) { throw "Expected $ExpectedError from ${Method}: $($response | ConvertTo-Json -Compress)" }
    } elseif ($response.error) {
      throw "${Method}: $($response.error | ConvertTo-Json -Compress)"
    }
    return $response
  }
}

try {
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while (!(Test-Path $portFile) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
  $httpPort = [int](Get-Content $portFile)
  $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
  $portProbe.Start()
  $mixedPort = $portProbe.LocalEndpoint.Port
  $portProbe.Stop()
  $connection = $pipe.WaitForConnectionAsync()
  $started = Invoke-RestMethod -Uri 'http://127.0.0.1:47891/start' -Method Post -ContentType 'application/json' -Body (@{ address = "\\.\pipe\$pipeName"; sessionId = $sessionId } | ConvertTo-Json)
  if ($started.sessionId -ne $sessionId -or $started.pid -le 0) { throw 'Invalid Helper start response' }
  if (!$connection.Wait(15000)) { throw 'Core did not connect to its named pipe' }
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class ElephantPipePeer {
  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool GetNamedPipeClientProcessId(IntPtr pipe, out uint processId);
}
'@
  $peerProcessId = [uint32]0
  if (![ElephantPipePeer]::GetNamedPipeClientProcessId($pipe.SafePipeHandle.DangerousGetHandle(), [ref]$peerProcessId) -or $peerProcessId -ne $started.pid) { throw 'Named-pipe peer does not match Helper-owned Core' }
  $checks.named_pipe_peer_identity = $true
  Invoke-Core 'core.init' @{ 'home-dir' = $runtimeHome; version = 22201 } | Out-Null
  if (!(Invoke-Core 'core.initialized').result) { throw 'Core initialization failed' }
  $config = @{
    'mixed-port' = $mixedPort
    mode = 'rule'
    dns = @{ enable = $true; listen = ''; 'enhanced-mode' = 'fake-ip'; nameserver = @('https://1.1.1.1/dns-query') }
    'proxy-groups' = @(@{ name = 'Exit'; type = 'select'; proxies = @('DIRECT') })
    rules = @('MATCH,Exit')
    tun = @{ enable = $false; device = 'ElephantArmTest'; stack = 'mixed'; 'auto-route' = $false; 'auto-detect-interface' = $false }
  }
  $config | ConvertTo-Json -Depth 100 | Set-Content (Join-Path $runtimeHome 'config.yaml') -Encoding utf8
  Invoke-Core 'config.setup' @{ 'selected-map' = @{ Exit = 'DIRECT' } } | Out-Null
  $before = (Invoke-Core 'proxy.list').result | ConvertTo-Json -Depth 100 -Compress
  Invoke-Core 'config.updateRuntime' @{ hosts = @{ 'test.invalid' = '127.0.0.2' }; ntp = @{ enable = $false }; sniffer = @{ enable = $false } } | Out-Null
  $after = (Invoke-Core 'proxy.list').result | ConvertTo-Json -Depth 100 -Compress
  if ($before -ne $after) { throw 'Runtime update changed proxy groups' }
  Invoke-Core 'config.updateRuntime' @{ dns = @{ enable = $true; nameserver = @('unsupported://resolver') } } 'core_error' | Out-Null
  if (((Invoke-Core 'proxy.list').result | ConvertTo-Json -Depth 100 -Compress) -ne $before) { throw 'Rejected update changed proxy groups' }
  $checks.runtime_updates_preserve_groups = $true
  Invoke-Core 'dns.clearCache' | Out-Null
  Invoke-Core 'network.changed' | Out-Null
  $fast = (Invoke-Core 'proxy.testDelay' @{ 'proxy-name' = 'DIRECT'; timeout = 3000; 'test-url' = "http://127.0.0.1:$httpPort/fast" }).result
  if ($fast.value -lt 1) { throw 'Local direct delay probe failed' }
  $slow = (Invoke-Core 'proxy.testDelay' @{ 'proxy-name' = 'DIRECT'; timeout = 100; 'test-url' = "http://127.0.0.1:$httpPort/slow" }).result
  if ($slow.value -ne -1) { throw 'Delay probe ignored its timeout' }
  $checks.delay_probe_and_timeout = $true
  Invoke-Core 'listener.start' | Out-Null
  $proxyClient = [Net.Sockets.TcpClient]::new('127.0.0.1', $mixedPort)
  try {
    $stream = $proxyClient.GetStream()
    $stream.ReadTimeout = 10000
    $request = [Text.Encoding]::ASCII.GetBytes("GET http://127.0.0.1:$httpPort/fast HTTP/1.1`r`nHost: 127.0.0.1:$httpPort`r`nConnection: close`r`n`r`n")
    $stream.Write($request, 0, $request.Length)
    $reader = [IO.StreamReader]::new($stream)
    $statusLine = $reader.ReadLine()
    if ($statusLine -notmatch '^HTTP/1\.[01] 204 ') { throw "HTTP proxy forwarding failed: $statusLine" }
    $checks.local_http_proxy_forwarding = $true
  } finally {
    $proxyClient.Dispose()
  }
  Invoke-Core 'config.update' @{ tun = @{ enable = $true } } | Out-Null
  $adapter = Get-NetAdapter -Name 'ElephantArmTest' -IncludeHidden
  if (!$adapter) { throw 'ARM64 TUN adapter was not created' }
  $checks.tun_adapter = @{ name = $adapter.Name; description = $adapter.InterfaceDescription; status = [string]$adapter.Status }
  Invoke-Core 'config.update' @{ tun = @{ enable = $false } } | Out-Null
  Invoke-Core 'listener.stop' | Out-Null
  $checks.tun_enable_disable = $true
  $config.proxies = @(0..19999 | ForEach-Object { @{ name = "node-$_"; type = 'socks5'; server = '127.0.0.1'; port = 1080 } })
  $profile = Join-Path $runtimeHome 'large.yaml'
  $config | ConvertTo-Json -Depth 100 | Set-Content $profile -Encoding utf8
  $large = Invoke-Core 'config.read' @{ path = $profile }
  if ($large.result.proxies.Count -ne 20000 -or $script:spilledResponses -ne 1) { throw 'Large-response transport failed' }
  if (@(Get-ChildItem (Join-Path $runtimeHome 'responses') -Filter '*.json').Count -ne 0) { throw 'Response files were not cleaned up' }
  $checks.large_response_proxies = 20000
  Invoke-Core 'core.shutdown' | Out-Null
} finally {
  $pipe.Dispose()
  if (!$httpServer.HasExited) { $httpServer.Kill(); $httpServer.WaitForExit(10000) | Out-Null }
  $stopped = Invoke-RestMethod -Uri 'http://127.0.0.1:47891/stop' -Method Post -ContentType 'application/json' -Body (@{ sessionId = $sessionId } | ConvertTo-Json)
  if ($stopped.sessionId -ne $sessionId) { throw 'Helper stopped the wrong Core session' }
}

$app = Start-Process -FilePath (Join-Path $InstallDirectory 'ElephantNetwork.exe') -WorkingDirectory $InstallDirectory -RedirectStandardOutput (Join-Path $runtimeHome 'app.stdout.log') -RedirectStandardError (Join-Path $runtimeHome 'app.stderr.log') -PassThru
try {
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 500
    $app.Refresh()
    if ($app.HasExited) { throw "Application exited during startup: $($app.ExitCode)" }
  } while ($app.MainWindowHandle -eq 0 -and [DateTime]::UtcNow -lt $deadline)
  if ($app.MainWindowHandle -eq 0) { throw 'Application did not create a desktop window' }
  Start-Sleep -Seconds 10
  $app.Refresh()
  if ($app.HasExited) { throw 'Application exited after window creation' }
  $checks.desktop_window_startup = $true
} finally {
  if (!$app.HasExited) { $app.Kill(); $app.WaitForExit(10000) | Out-Null }
  Get-Content (Join-Path $runtimeHome 'app.stdout.log'), (Join-Path $runtimeHome 'app.stderr.log') -ErrorAction SilentlyContinue
  Copy-Item $runtimeHome (Join-Path (Split-Path $Receipt) 'windows-runtime-logs') -Recurse -Force
}

$checks | ConvertTo-Json -Depth 100 | Set-Content $Receipt -Encoding utf8
$checks | ConvertTo-Json -Depth 100
