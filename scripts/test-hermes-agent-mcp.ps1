param(
	[switch]$Json,
	[switch]$SummaryOnly,
	[switch]$RealRun,
	[string]$Model = "local/Qwen3.6-27B-Q4_0",
	[string]$Provider = "custom",
	[string]$Prompt = "Reply with exactly OK.",
	[int]$TimeoutMs = 300000,
	[string]$ResultPath = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$serverScript = Join-Path $scriptRoot "mcp\hermes-agent-server.js"

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

function Send-RawMcpBody {
	param(
		[System.Diagnostics.Process]$Process,
		[string]$Body
	)
	$length = [System.Text.Encoding]::UTF8.GetByteCount($Body)
	$text = "Content-Length: $length`r`n`r`n$Body"
	$bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
	$Process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
	$Process.StandardInput.BaseStream.Flush()
}

function Assert-McpToolError {
	param(
		[System.Diagnostics.Process]$Process,
		[int]$Id,
		[hashtable]$Arguments,
		[string]$Pattern
	)
	Assert-McpNamedToolError -Process $Process -Id $Id -ToolName "run_hermes_agent" -Arguments $Arguments -Pattern $Pattern
}

function Assert-McpNamedToolError {
	param(
		[System.Diagnostics.Process]$Process,
		[int]$Id,
		[string]$ToolName,
		[hashtable]$Arguments,
		[string]$Pattern
	)
	Send-McpMessage $Process @{
		jsonrpc = "2.0"
		id = $Id
		method = "tools/call"
		params = @{
			name = $ToolName
			arguments = $Arguments
		}
	}
	$response = Read-McpMessage $Process.StandardOutput.BaseStream
	if (!$response.error) {
		throw "MCP tools/call $Id ($ToolName) unexpectedly succeeded."
	}
	if ([int]$response.id -ne $Id) {
		throw "MCP tools/call $Id did not preserve the JSON-RPC id."
	}
	if ([string]$response.error.message -notmatch $Pattern) {
		throw "MCP tools/call $Id error did not match ${Pattern}: $($response.error.message)"
	}
}

if (!(Test-Path -LiteralPath $serverScript -PathType Leaf)) {
	throw "Hermes agent MCP server was not found: $serverScript"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (!$node) {
	throw "Hermes agent MCP smoke requires node, but node was not found."
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
$oldAllowedRoots = $env:OFXGGML_HERMES_ALLOWED_ROOTS
$oldSafeToolsets = $env:OFXGGML_HERMES_SAFE_TOOLSETS
$oldHermesToolsets = $env:OFXGGML_HERMES_TOOLSETS
$oldAllowHooks = $env:OFXGGML_HERMES_ALLOW_HOOKS
$oldOutputLimit = $env:OFXGGML_HERMES_OUTPUT_LIMIT_BYTES
$oldTimeout = $env:OFXGGML_HERMES_TIMEOUT_MS
$oldMaxTimeout = $env:OFXGGML_HERMES_MAX_TIMEOUT_MS
$oldEndpointAllowlist = $env:OFXGGML_HERMES_ENDPOINT_ALLOWLIST
$oldSafeMode = $env:OFXGGML_HERMES_SAFE_MODE
$env:OFXGGML_HERMES_ALLOWED_ROOTS = $addonRoot.Path
$env:OFXGGML_HERMES_SAFE_TOOLSETS = "web,skills,session_search,clarify,todo"
$env:OFXGGML_HERMES_TOOLSETS = "web,skills"
$env:OFXGGML_HERMES_ALLOW_HOOKS = "0"
$env:OFXGGML_HERMES_OUTPUT_LIMIT_BYTES = "8192"
$env:OFXGGML_HERMES_MAX_TIMEOUT_MS = "120000"
$env:OFXGGML_HERMES_ENDPOINT_ALLOWLIST = "http://127.0.0.1:8001/v1,http://localhost:8001/v1"
$env:OFXGGML_HERMES_SAFE_MODE = "1"
if ($RealRun) {
	$env:OFXGGML_HERMES_TIMEOUT_MS = [string]$TimeoutMs
	$env:OFXGGML_HERMES_ALLOW_HOOKS = "1"
	$env:OFXGGML_HERMES_SAFE_MODE = "0"
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
	if (!$initialize.result.serverInfo -or $initialize.result.serverInfo.name -ne "ofxggml-hermes-agent") {
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
	if ("run_hermes_agent" -notin $toolNames) {
		throw "MCP tools/list did not expose run_hermes_agent."
	}
	if ("preflight_hermes_agent" -notin $toolNames) {
		throw "MCP tools/list did not expose preflight_hermes_agent."
	}
	$runTool = @($tools.result.tools | Where-Object { $_.name -eq "run_hermes_agent" })[0]
	if (!$runTool -or [string]$runTool.type -ne "function") {
		throw "MCP tools/list did not expose run_hermes_agent as an OpenAI-compatible function tool."
	}
	if (!$runTool.function -or [string]$runTool.function.name -ne "run_hermes_agent") {
		throw "MCP tools/list did not expose a matching function envelope for run_hermes_agent."
	}
	if (!$runTool.function.parameters -or [string]$runTool.function.parameters.type -ne "object") {
		throw "MCP tools/list did not expose function parameters for run_hermes_agent."
	}

	Assert-McpToolError -Process $process -Id 20 -Arguments @{
		cwd = $addonRoot.Path
		dry_run = $true
	} -Pattern "prompt is required"
	Assert-McpToolError -Process $process -Id 21 -Arguments @{
		prompt = "Reject this invalid cwd."
		cwd = [System.IO.Path]::GetPathRoot($addonRoot.Path)
		dry_run = $true
	} -Pattern "outside the allowed Hermes roots"
	Assert-McpToolError -Process $process -Id 23 -Arguments @{
		prompt = "Reject unsafe toolset."
		cwd = $addonRoot.Path
		toolsets = "terminal"
		dry_run = $true
	} -Pattern "outside OFXGGML_HERMES_SAFE_TOOLSETS"
	Assert-McpToolError -Process $process -Id 26 -Arguments @{
		prompt = "Reject hooks without env policy."
		cwd = $addonRoot.Path
		allow_hooks = $true
		dry_run = $true
	} -Pattern "OFXGGML_HERMES_ALLOW_HOOKS=1"
	Assert-McpNamedToolError -Process $process -Id 27 -ToolName "preflight_hermes_agent" -Arguments @{
		cwd = $addonRoot.Path
		endpoint = "http://127.0.0.1:1/v1"
		check_endpoint = $true
	} -Pattern "outside OFXGGML_HERMES_ENDPOINT_ALLOWLIST"

	Send-RawMcpBody -Process $process -Body "{not-json"
	$parseError = Read-McpMessage $process.StandardOutput.BaseStream
	if (!$parseError.error -or [int]$parseError.error.code -ne -32700) {
		throw "MCP server did not return a JSON-RPC parse error for malformed input."
	}

	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 22
		method = "tools/call"
		params = @{
			name = "run_hermes_agent"
			arguments = @{
				prompt = "Use fallback timeout."
				cwd = $addonRoot.Path
				timeout_ms = "not-a-number"
				dry_run = $true
			}
		}
	}
	$timeoutFallback = Read-McpMessage $process.StandardOutput.BaseStream
	if ($timeoutFallback.error) {
		throw "MCP timeout fallback call failed: $($timeoutFallback.error.message)"
	}
	$timeoutPlan = [string]$timeoutFallback.result.content[0].text | ConvertFrom-Json
	if ([int]$timeoutPlan.command.timeoutMs -ne 120000) {
		throw "Hermes MCP dry-run did not clamp timeout_ms to OFXGGML_HERMES_MAX_TIMEOUT_MS."
	}
	if ($timeoutPlan.command.args -contains "--accept-hooks") {
		throw "Hermes MCP dry-run enabled --accept-hooks by default."
	}
	if ($timeoutPlan.command.args -notcontains "--safe-mode") {
		throw "Hermes MCP dry-run did not use env-provided --safe-mode."
	}
	if ($timeoutPlan.command.args -notcontains "-t" -or $timeoutPlan.command.args -notcontains "web,skills") {
		throw "Hermes MCP dry-run did not use env-provided safe toolsets."
	}
	if ([int]$timeoutPlan.command.outputLimitBytes -ne 8192) {
		throw "Hermes MCP dry-run did not include the env-provided output limit."
	}

	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 25
		method = "tools/call"
		params = @{
			name = "preflight_hermes_agent"
			arguments = @{
				cwd = $addonRoot.Path
				model = $Model
				provider = $Provider
				check_endpoint = $false
			}
		}
	}
	$preflight = Read-McpMessage $process.StandardOutput.BaseStream
	if ($preflight.error) {
		throw "MCP Hermes preflight failed: $($preflight.error.message)"
	}
	$preflightPlan = [string]$preflight.result.content[0].text | ConvertFrom-Json
	if (!$preflightPlan.hermes -or !$preflightPlan.command -or $preflightPlan.endpoint.skipped -ne $true) {
		throw "Hermes MCP preflight did not return the expected structured result."
	}
	if (!$RealRun -and $preflightPlan.command.safeMode -ne $true) {
		throw "Hermes MCP preflight did not report env-provided safe mode."
	}

	$toolArguments = @{
		prompt = if ($RealRun) { $Prompt } else { "Summarize the Hermes sidecar plan." }
		cwd = $addonRoot.Path
		model = $Model
		provider = $Provider
		dry_run = !$RealRun
	}
	if ($RealRun) {
		$toolArguments.allow_hooks = $true
	}
	Send-McpMessage $process @{
		jsonrpc = "2.0"
		id = 3
		method = "tools/call"
		params = @{
			name = "run_hermes_agent"
			arguments = $toolArguments
		}
	}
	$call = Read-McpMessage $process.StandardOutput.BaseStream
	if ($call.error) {
		throw "MCP tools/call failed: $($call.error.message)"
	}
	$text = [string]$call.result.content[0].text
	if ($RealRun) {
		if (!$text.Trim()) {
			throw "Hermes real run returned an empty response."
		}
	} else {
		if ($text -notmatch "hermes one-shot cli" -or $text -notmatch "Summarize the Hermes sidecar plan") {
			throw "MCP dry-run did not describe the planned Hermes command."
		}
		$plan = $text | ConvertFrom-Json
		if ($plan.command.args -notcontains "-z" -or $plan.command.args -notcontains "--provider") {
			throw "Hermes MCP dry-run did not include expected CLI arguments."
		}
		if ($plan.command.args -contains "--accept-hooks") {
			throw "Hermes MCP dry-run unexpectedly included --accept-hooks."
		}
		if ($plan.command.args -notcontains $Model -or $plan.command.args -notcontains $Provider) {
			throw "Hermes MCP dry-run did not use the requested model/provider."
		}
		if ($plan.command.args -notcontains "-t" -or $plan.command.args -notcontains "web,skills") {
			throw "Hermes MCP dry-run did not include the safe env toolsets."
		}
		if (@($plan.command.allowedCwdRoots).Count -lt 1 -or $plan.command.cwd -ne $addonRoot.Path) {
			throw "Hermes MCP dry-run did not constrain the run cwd to the addon root."
		}
	}

	$result = [ordered]@{
		status = "passed"
		serverScript = $serverScript
		tool = "run_hermes_agent"
		mode = if ($RealRun) { "real-run" } else { "dry-run" }
		model = $Model
		provider = $Provider
	}
	if ($ResultPath) {
		$resolvedResultPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ResultPath)
		[pscustomobject]$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $resolvedResultPath -Encoding UTF8
	}
	if ($Json) {
		Write-Output ([pscustomobject]$result | ConvertTo-Json -Depth 4)
	} elseif (!$SummaryOnly) {
		Write-Host "Hermes agent MCP checks passed."
	}
} finally {
	$env:OFXGGML_HERMES_ALLOWED_ROOTS = $oldAllowedRoots
	$env:OFXGGML_HERMES_SAFE_TOOLSETS = $oldSafeToolsets
	$env:OFXGGML_HERMES_TOOLSETS = $oldHermesToolsets
	$env:OFXGGML_HERMES_ALLOW_HOOKS = $oldAllowHooks
	$env:OFXGGML_HERMES_OUTPUT_LIMIT_BYTES = $oldOutputLimit
	$env:OFXGGML_HERMES_TIMEOUT_MS = $oldTimeout
	$env:OFXGGML_HERMES_MAX_TIMEOUT_MS = $oldMaxTimeout
	$env:OFXGGML_HERMES_ENDPOINT_ALLOWLIST = $oldEndpointAllowlist
	$env:OFXGGML_HERMES_SAFE_MODE = $oldSafeMode
	if (!$process.HasExited) {
		$process.Kill()
		$process.WaitForExit()
	}
}
