param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-FreeTcpPort {
	$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
	$listener.Start()
	try {
		return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
	} finally {
		$listener.Stop()
	}
}

function Start-TestListener {
	param([string]$Executable, [int]$Port)
	$serverScript = @"
`$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
`$listener.Start()
try {
	while (`$true) { Start-Sleep -Seconds 1 }
} finally {
	`$listener.Stop()
}
"@
	$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($serverScript))
	return Start-Process `
		-FilePath $Executable `
		-ArgumentList @("-NoProfile", "-EncodedCommand", $encodedCommand) `
		-WindowStyle Hidden `
		-PassThru
}

function Wait-ListeningPort {
	param([int]$Port)
	for ($attempt = 0; $attempt -lt 30; $attempt++) {
		$lines = @(& netstat.exe -ano -p tcp 2>$null)
		if (@(Get-OfxGgmlNetstatPortOwnerProcessIds -NetstatLines $lines -Port $Port).Count -gt 0) {
			return
		}
		Start-Sleep -Milliseconds 100
	}
	throw "Test listener did not bind port $Port."
}

function Stop-TestProcess {
	param([Diagnostics.Process]$Process)
	if ($Process -and !$Process.HasExited) {
		Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
		[void]$Process.WaitForExit(2000)
	}
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")
$launcher = Join-Path $scriptRoot "start-llama-server.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("ofxGgmlLlama-force-new-" + [guid]::NewGuid().ToString("N"))
$fakeServer = Join-Path $testRoot "llama-server.exe"
$modelPath = Join-Path $testRoot "model.gguf"
$targetProcess = $null
$otherProcess = $null

try {
	[void](New-Item -ItemType Directory -Path $testRoot -Force)
	Copy-Item -LiteralPath ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) -Destination $fakeServer
	[void](New-Item -ItemType File -Path $modelPath)
	$targetPort = Get-FreeTcpPort
	$otherPort = Get-FreeTcpPort
	$targetProcess = Start-TestListener -Executable $fakeServer -Port $targetPort
	$otherProcess = Start-TestListener -Executable $fakeServer -Port $otherPort
	Wait-ListeningPort -Port $targetPort
	Wait-ListeningPort -Port $otherPort

	try {
		& $launcher `
			-ModelPath $modelPath `
			-ServerExe $fakeServer `
			-Port $targetPort `
			-Alias "test-model" `
			-ForceNew `
			-Detached `
			-StartupTimeoutSeconds 1 *> $null
	} catch {
		# The copied PowerShell host is intentionally not a real llama-server.
	}

	[void]$targetProcess.WaitForExit(3000)
	$targetProcess.Refresh()
	$otherProcess.Refresh()
	if (!$targetProcess.HasExited) {
		throw "ForceNew did not stop the listener on its selected port $targetPort."
	}
	if ($otherProcess.HasExited) {
		throw "ForceNew stopped the sibling listener on unrelated port $otherPort."
	}
	Write-Host "==> llama-server ForceNew port scope passed"
} finally {
	Stop-TestProcess -Process $targetProcess
	Stop-TestProcess -Process $otherProcess
	Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
