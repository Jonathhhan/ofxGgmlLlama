param(
	[switch]$IncludeExamples,
	[switch]$All,
	[switch]$DryRun
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Get-ProcessPath {
	param([System.Diagnostics.Process]$Process)
	try {
		return [string]$Process.Path
	} catch {
		return ""
	}
}

function Get-TargetProcesses {
	$names = @("llama-server")
	if ($IncludeExamples) {
		$names += @(
			"example-text",
			"example-chat",
			"example-emb"
		)
	}

	$addonPath = $addonRoot.Path
	return @(Get-Process -Name $names -ErrorAction SilentlyContinue |
		Where-Object {
			if ($All) {
				return $true
			}
			$processPath = Get-ProcessPath $_
			![string]::IsNullOrWhiteSpace($processPath) -and
				$processPath.StartsWith($addonPath, [System.StringComparison]::OrdinalIgnoreCase)
		} |
		Sort-Object ProcessName,Id)
}

Write-Host "llama-server stop plan"
Write-Host "  root:            $addonRoot"
Write-Host "  includeExamples: $(if ($IncludeExamples) { 'on' } else { 'off' })"
Write-Host "  scope:           $(if ($All) { 'all matching processes' } else { 'this addon only' })"
Write-Host "  mode:            $(if ($DryRun) { 'dry-run' } else { 'stop' })"

$targets = @(Get-TargetProcesses)
if ($targets.Count -eq 0) {
	Write-Step "No matching processes found"
	return
}

foreach ($process in $targets) {
	$processPath = Get-ProcessPath $process
	Write-Host ("  {0}({1}) {2}" -f $process.ProcessName, $process.Id, $processPath)
}

if ($DryRun) {
	Write-Step "Dry run complete; no processes were stopped"
	return
}

foreach ($process in $targets) {
	Stop-Process -Id $process.Id -Force -ErrorAction Stop
}

Write-Step "Stopped $($targets.Count) process(es)"
