param(
	[switch]$Json,
	[switch]$SummaryOnly,
	[switch]$RealSpawn,
	[string]$Model = "local/Qwen3.6-27B-Q4_0",
	[string]$ModelProvider = "llama_cpp",
	[string]$CodexExe = $(if ($env:OFXGGML_CODEX_EXE) { $env:OFXGGML_CODEX_EXE } else { "" }),
	[string]$Prompt = "Reply with exactly OK.",
	[int]$TimeoutMs = 90000,
	[string]$ResultPath = "",
	[switch]$OmitModelArgument
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$serverScript = Join-Path $scriptRoot "mcp\codex-thread-server.js"

function New-McpMessage {
	param([object]$Message)
	$json = $Message | ConvertTo-Json -Depth 8 -Compress
	$length = [System.Text.Encoding]::UTF8.GetByteCount($json)
	return "Content-Length: $length`r`n`r`n$json"
}

function Read-ExactBytes {
	param(
		[System.IO.Stream]$Stream,
		[int]$Length
	)
	$buffer = New-Object byte[] $Length
	$offset = 0
	while ($offset -lt $Length) {
		$count = $Stream.Read($buffer, $offset, $Length - $offset)
		if ($count -le 0) {
			throw "unexpected end of MCP stream"
		}
		$offset += $count
	}
	return $buffer
}

function Read-McpMessage {
	param([System.IO.Stream]$Stream)
	$headerBytes = New-Object System.Collections.Generic.List[byte]
	$tail = ""
	while ($true) {
		$byte = $Stream.ReadByte()
		if ($byte -lt 0) {
			throw "MCP server closed before sending a response"
		}
		[void]$headerBytes.Add([byte]$byte)
		$tail += [char]$byte
		if ($tail.Length -gt 4) {
			$tail = $tail.Substring($tail.Length - 4)
		}
		if ($tail -eq "`r`n`r`n") {
			break
		}
	}
	$header = [System.Text.Encoding]::ASCII.GetString($headerBytes.ToArray())
	if ($header -notmatch "Content-Length:\s*(\d+)") {
		throw "MCP response missing Content-Length header: $header"
	}
	$bodyBytes = Read-ExactBytes -Stream $Stream -Length ([int]$Matches[1])
	$body = [System.Text.Encoding]::UTF8.GetString($bodyBytes)
	return $body | ConvertFrom-Json
}

function Send-McpMessage {
	param(
		[System.Diagnostics.Process]$Process,
		[object]$Message
	)
	$text = New-McpMessage $Message
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
	$Process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
	$Process.StandardInput.BaseStream.Flush()
}

if (!(Test-Path -LiteralPath $serverScript -PathType Leaf)) {
	throw "Codex thread MCP server was not found: $serverScript"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (!$node) {
	Write-Warning "Skipping Codex thread MCP smoke because node was not found."
	exit 0
}

if ([string]::IsNullOrWhiteSpace($CodexExe)) {
	$knownCodex = @()
	if ($env:LOCALAPPDATA) {
		$knownCodex += (Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\codex.exe")
	}
	if ($env:USERPROFILE) {
		$knownCodex += (Join-Path $env:USERPROFILE "AppData\Local\OpenAI\Codex\bin\codex.exe")
	}
	foreach ($candidate in $knownCodex) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			$CodexExe = (Resolve-Path -LiteralPath $candidate).Path
			break
		}
	}
}
if (![string]::IsNullOrWhiteSpace($CodexExe) -and (Test-Path -LiteralPath $CodexExe -PathType Leaf)) {
	$CodexExe = (Resolve-Path -LiteralPath $CodexExe).Path
}

$processInfo = [System.Diagnostics.ProcessStartInfo]::new()
$processInfo.FileName = $node.Source
$processInfo.Arguments = "`"$serverScript`""
$processInfo.WorkingDirectory = $addonRoot.Path
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardInput = $true
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.CreateNoWindow = $true

$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $processInfo
$oldThreadTimeout = $env:OFXGGML_CODEX_THREAD_SPAWN_TIMEOUT_MS
$oldCodexExe = $env:OFXGGML_CODEX_EXE
if ($RealSpawn) {
	$env:OFXGGML_CODEX_THREAD_SPAWN_TIMEOUT_MS = [string]$TimeoutMs
}
if (![string]::IsNullOrWhiteSpace($CodexExe)) {
	$env:OFXGGML_CODEX_EXE = $CodexExe
}
[void]$process.Start()
try {
	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 1
		method = "initialize"
		params = @{
			protocolVersion = "2024-11-05"
			capabilities = @{}
			clientInfo = @{ name = "ofxggml-test"; version = "0.1.0" }
		}
	}
	$initialize = Read-McpMessage $process.StandardOutput.BaseStream
	if (!$initialize.result.serverInfo -or $initialize.result.serverInfo.name -ne "ofxggml-codex-thread-spawner") {
		throw "MCP initialize did not return the expected server name."
	}

	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 2
		method = "tools/list"
		params = @{}
	}
	$tools = Read-McpMessage $process.StandardOutput.BaseStream
	$toolNames = @($tools.result.tools | ForEach-Object { $_.name })
	if ("spawn_codex_thread" -notin $toolNames) {
		throw "MCP tools/list did not expose spawn_codex_thread."
	}

	$toolArguments = @{
		prompt = if ($RealSpawn) { $Prompt } else { "Summarize the local Codex plan." }
		cwd = $addonRoot.Path
		dry_run = !$RealSpawn
	}
	if (!$OmitModelArgument) {
		$toolArguments.model = $Model
		$toolArguments.model_provider = $ModelProvider
	}
	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 3
		method = "tools/call"
		params = @{
			name = "spawn_codex_thread"
			arguments = $toolArguments
		}
	}
	$call = Read-McpMessage $process.StandardOutput.BaseStream
	if ($call.error) {
		throw "MCP tools/call failed: $($call.error.message)"
	}
	$text = [string]$call.result.content[0].text
	$spawn = $null
	if ($RealSpawn) {
		$spawn = $text | ConvertFrom-Json
		if ($spawn.status -ne "spawned" -or !$spawn.thread_id) {
			throw "MCP real-spawn did not return a spawned thread: $text"
		}
	} else {
		if ($text -notmatch "codex app-server stdio" -or $text -notmatch "Summarize the local Codex plan") {
			throw "MCP dry-run did not describe the planned Codex app-server thread."
		}
	}

	$result = [ordered]@{
		status = "passed"
		serverScript = $serverScript
		tool = "spawn_codex_thread"
		mode = if ($RealSpawn) { "real-spawn" } else { "dry-run" }
		model = $Model
		modelProvider = $ModelProvider
		codexExe = $CodexExe
		threadId = if ($spawn -and $spawn.thread_id) { [string]$spawn.thread_id } else { "" }
		turnStatus = if ($spawn -and $spawn.turn_status) { [string]$spawn.turn_status } else { "" }
		completed = if ($spawn -and $null -ne $spawn.completed) { [bool]$spawn.completed } else { $false }
	}
	if ($ResultPath) {
		$resolvedResultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultPath)
		[pscustomobject]$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resolvedResultPath -Encoding UTF8
	}
	if ($Json) {
		Write-Output ([pscustomobject]$result | ConvertTo-Json -Depth 4)
	} elseif (!$SummaryOnly) {
		Write-Host "Codex thread MCP checks passed."
	}
} finally {
	if ($RealSpawn) {
		$env:OFXGGML_CODEX_THREAD_SPAWN_TIMEOUT_MS = $oldThreadTimeout
	}
	if ($null -eq $oldCodexExe) {
		Remove-Item Env:\OFXGGML_CODEX_EXE -ErrorAction SilentlyContinue
	} else {
		$env:OFXGGML_CODEX_EXE = $oldCodexExe
	}
	if (!$process.HasExited) {
		$process.Kill()
		$process.WaitForExit()
	}
}
