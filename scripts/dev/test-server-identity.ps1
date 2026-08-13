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

function Start-IdentityServer {
	param([int]$Port, [string]$ModelId)
	$escapedModel = $ModelId.Replace("'", "''")
	$serverScript = @"
`$listenPort = $Port
`$servedModel = '$escapedModel'
`$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, `$listenPort)
`$listener.Start()
try {
	while (`$true) {
		`$client = `$listener.AcceptTcpClient()
		`$stream = `$client.GetStream()
		`$reader = [IO.StreamReader]::new(`$stream, [Text.Encoding]::ASCII, `$false, 1024, `$true)
		`$requestLine = `$reader.ReadLine()
		while (![string]::IsNullOrEmpty(`$reader.ReadLine())) {}
		`$path = if (`$requestLine) { (`$requestLine -split ' ')[1] } else { '' }
		`$body = if (`$path -eq '/health') {
			'{"status":"ok"}'
		} elseif (`$path -eq '/v1/models') {
			'{"data":[{"id":"' + `$servedModel + '"}]}'
		} else {
			'{"error":"not found"}'
		}
		`$bytes = [Text.Encoding]::UTF8.GetBytes(`$body)
		`$status = if (`$path -in @('/health', '/v1/models')) { '200 OK' } else { '404 Not Found' }
		`$header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 `$status`r`nContent-Type: application/json`r`nContent-Length: `$(`$bytes.Length)`r`nConnection: close`r`n`r`n")
		`$stream.Write(`$header, 0, `$header.Length)
		`$stream.Write(`$bytes, 0, `$bytes.Length)
		`$stream.Flush()
		`$client.Close()
	}
} finally {
	`$listener.Stop()
}
"@
	$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($serverScript))
	$runner = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
	$startParams = @{
		FilePath = $runner
		ArgumentList = @("-NoProfile", "-EncodedCommand", $encodedCommand)
		PassThru = $true
	}
	if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
		$startParams.WindowStyle = "Hidden"
	}
	return Start-Process @startParams
}

function Stop-IdentityServer {
	param([Diagnostics.Process]$Process)
	if ($Process -and !$Process.HasExited) {
		Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
		[void]$Process.WaitForExit(2000)
	}
}

function Wait-IdentityServer {
	param([int]$Port)
	for ($attempt = 0; $attempt -lt 20; $attempt++) {
		try {
			$response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -UseBasicParsing -TimeoutSec 1
			if ($response.StatusCode -eq 200) { return }
		} catch {}
		Start-Sleep -Milliseconds 100
	}
	throw "Identity test server did not become ready on port $Port."
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$launcher = Join-Path $scriptRoot "start-llama-server.ps1"
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("ofxGgmlLlama-server-identity-" + [guid]::NewGuid().ToString("N"))
$modelPath = Join-Path $testRoot "expected-model.gguf"
$serverExe = Join-Path $testRoot "llama-server.exe"
[void](New-Item -ItemType Directory -Path $testRoot -Force)
[void](New-Item -ItemType File -Path $modelPath, $serverExe)
$matchingJob = $null
$mismatchJob = $null

try {
	$matchingPort = Get-FreeTcpPort
	$matchingJob = Start-IdentityServer -Port $matchingPort -ModelId "expected-alias"
	Wait-IdentityServer -Port $matchingPort
	try {
		$matchingOutput = @(& $launcher `
			-ModelPath $modelPath `
			-ServerExe $serverExe `
			-Port $matchingPort `
			-Alias "expected-alias" *>&1 | ForEach-Object { [string]$_ })
		if (!$? -or ($matchingOutput -join "`n") -notmatch "identity verified" -or
			($matchingOutput -join "`n") -notmatch "Reusing the existing matching server") {
			throw "Matching llama-server identity was not reused.`n$($matchingOutput -join [Environment]::NewLine)"
		}
	} finally {
		Stop-IdentityServer -Process $matchingJob
	}

	$mismatchPort = Get-FreeTcpPort
	$mismatchJob = Start-IdentityServer -Port $mismatchPort -ModelId "other-alias"
	Wait-IdentityServer -Port $mismatchPort
	try {
		$mismatchFailed = $false
		$mismatchOutput = @()
		try {
			$mismatchOutput = @(& $launcher `
				-ModelPath $modelPath `
				-ServerExe $serverExe `
				-Port $mismatchPort `
				-Alias "expected-alias" *>&1 | ForEach-Object { [string]$_ })
		} catch {
			$mismatchFailed = $true
			$mismatchOutput += $_.Exception.Message
		}
		if (!$mismatchFailed -or ($mismatchOutput -join "`n") -notmatch "different model" -or
			($mismatchOutput -join "`n") -notmatch "other-alias" -or
			($mismatchOutput -join "`n") -notmatch "expected-alias") {
			throw "Mismatched llama-server identity was not rejected with both identities.`n$($mismatchOutput -join [Environment]::NewLine)"
		}
	} finally {
		Stop-IdentityServer -Process $mismatchJob
	}

	Write-Host "==> llama-server identity reuse and mismatch rejection passed"
} finally {
	Stop-IdentityServer -Process $matchingJob
	Stop-IdentityServer -Process $mismatchJob
	Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
