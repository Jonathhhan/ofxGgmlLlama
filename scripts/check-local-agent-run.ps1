param(
	[string]$ContractPath = "",
	[string]$RepoRoot = "",
	[string[]]$AllowedPath = @(),
	[string[]]$RequiredCommand = @(),
	[switch]$IncludeUntracked,
	[switch]$DryRun,
	[switch]$Json,
	[switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

function ConvertTo-ForwardSlash {
	param([string]$Value)
	return ($Value -replace "\\", "/").Trim("/")
}

function Test-PathAllowed {
	param(
		[string]$ChangedPath,
		[string[]]$AllowedPaths
	)
	if ($AllowedPaths.Count -eq 0) {
		return $true
	}
	$normalizedChanged = ConvertTo-ForwardSlash $ChangedPath
	foreach ($allowedPath in $AllowedPaths) {
		$normalizedAllowed = ConvertTo-ForwardSlash $allowedPath
		if ([string]::IsNullOrWhiteSpace($normalizedAllowed)) {
			continue
		}
		if ($normalizedChanged -eq $normalizedAllowed -or
			$normalizedChanged.StartsWith($normalizedAllowed.TrimEnd("/") + "/")) {
			return $true
		}
	}
	return $false
}

function Resolve-PowerShellRunner {
	$candidates = New-Object System.Collections.Generic.List[string]
	try {
		$currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
		if ($currentProcess.MainModule -and $currentProcess.MainModule.FileName) {
			$candidates.Add([string]$currentProcess.MainModule.FileName)
		}
	} catch {
	}
	foreach ($commandName in @("pwsh", "powershell", "powershell.exe")) {
		$command = Get-Command $commandName -ErrorAction SilentlyContinue
		if ($command -and $command.Source) {
			$candidates.Add([string]$command.Source)
		}
	}
	foreach ($candidate in $candidates) {
		if (![string]::IsNullOrWhiteSpace($candidate) -and
			(Test-Path -LiteralPath $candidate -PathType Leaf)) {
			return $candidate
		}
	}
	throw "Could not find a PowerShell executable for required command checks."
}

function Test-ExecutionPolicyArgumentSupported {
	param([string]$Runner)
	return (($env:OS -eq "Windows_NT" -or $PSVersionTable.PSEdition -eq "Desktop") -and
		([System.IO.Path]::GetFileName($Runner) -match "^(pwsh|powershell)(\.exe)?$"))
}

function Invoke-RequiredCommand {
	param(
		[string]$Command,
		[string]$WorkingDirectory,
		[bool]$DryRunOnly
	)
	if ($DryRunOnly) {
		return [pscustomobject]@{
			cmd = $Command
			status = 0
			dryRun = $true
		}
	}
	$powerShellRunner = Resolve-PowerShellRunner
	$arguments = @("-NoProfile")
	if (Test-ExecutionPolicyArgumentSupported $powerShellRunner) {
		$arguments += @("-ExecutionPolicy", "Bypass")
	}
	$arguments += @("-Command", $Command)
	Push-Location $WorkingDirectory
	try {
		& $powerShellRunner @arguments
		return [pscustomobject]@{
			cmd = $Command
			status = [int]$LASTEXITCODE
			dryRun = $false
			runner = $powerShellRunner
		}
	} finally {
		Pop-Location
	}
}

function Invoke-GitNameList {
	param(
		[string]$WorkingDirectory,
		[string[]]$Arguments
	)
	$previousErrorActionPreference = $ErrorActionPreference
	$ErrorActionPreference = "Continue"
	try {
		return @(& git -C $WorkingDirectory @Arguments 2>$null)
	} finally {
		$ErrorActionPreference = $previousErrorActionPreference
	}
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$contract = $null
$contractDirectory = ""
if (![string]::IsNullOrWhiteSpace($ContractPath)) {
	$resolvedContractPath = Resolve-Path $ContractPath
	$contractDirectory = Split-Path -Parent $resolvedContractPath.Path
	$contract = Get-Content -LiteralPath $resolvedContractPath.Path -Raw | ConvertFrom-Json
	if ($contract.repoRoot -and [string]::IsNullOrWhiteSpace($RepoRoot)) {
		$contractRepoRoot = [string]$contract.repoRoot
		if ([System.IO.Path]::IsPathRooted($contractRepoRoot)) {
			$RepoRoot = $contractRepoRoot
		} else {
			$RepoRoot = Join-Path $contractDirectory $contractRepoRoot
		}
	}
	if ($contract.allowedPaths) {
		$AllowedPath = @($contract.allowedPaths) + @($AllowedPath)
	}
	if ($contract.requiredCommands) {
		$RequiredCommand = @($contract.requiredCommands) + @($RequiredCommand)
	}
	if ($contract.includeUntracked -and !$IncludeUntracked) {
		$IncludeUntracked = $true
	}
}
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
	$RepoRoot = $addonRoot.Path
}
$resolvedRepoRoot = Resolve-Path $RepoRoot

$changedFiles = New-Object System.Collections.Generic.List[string]
$diffNames = Invoke-GitNameList $resolvedRepoRoot.Path @("diff", "--name-only")
foreach ($name in $diffNames) {
	if (![string]::IsNullOrWhiteSpace($name)) {
		$changedFiles.Add((ConvertTo-ForwardSlash $name))
	}
}
$stagedNames = Invoke-GitNameList $resolvedRepoRoot.Path @("diff", "--cached", "--name-only")
foreach ($name in $stagedNames) {
	if (![string]::IsNullOrWhiteSpace($name)) {
		$normalized = ConvertTo-ForwardSlash $name
		if (!$changedFiles.Contains($normalized)) {
			$changedFiles.Add($normalized)
		}
	}
}
if ($IncludeUntracked) {
	$untrackedNames = Invoke-GitNameList $resolvedRepoRoot.Path @("ls-files", "--others", "--exclude-standard")
	foreach ($name in $untrackedNames) {
		if (![string]::IsNullOrWhiteSpace($name)) {
			$normalized = ConvertTo-ForwardSlash $name
			if (!$changedFiles.Contains($normalized)) {
				$changedFiles.Add($normalized)
			}
		}
	}
}

$violations = New-Object System.Collections.Generic.List[string]
foreach ($changedFile in $changedFiles) {
	if (!(Test-PathAllowed $changedFile $AllowedPath)) {
		$violations.Add($changedFile)
	}
}

$commands = New-Object System.Collections.Generic.List[object]
foreach ($command in $RequiredCommand) {
	if ([string]::IsNullOrWhiteSpace($command)) {
		continue
	}
	$commandResult = Invoke-RequiredCommand `
		-Command $command `
		-WorkingDirectory $resolvedRepoRoot.Path `
		-DryRunOnly:$DryRun
	$commands.Add($commandResult)
}

$commandFailures = @($commands | Where-Object { $_.status -ne 0 })
$scopeOk = $violations.Count -eq 0
$commandsOk = $commandFailures.Count -eq 0
$status = if ($scopeOk -and $commandsOk) { "verified" } else { "failed" }
$normalizedAllowedPaths = @($AllowedPath | ForEach-Object { ConvertTo-ForwardSlash $_ })
$changedFileArray = @($changedFiles.ToArray())
$scopeViolationArray = @($violations.ToArray())
$commandArray = @($commands.ToArray())
$result = [pscustomobject]@{
	status = $status
	repoRoot = $resolvedRepoRoot.Path
	contractPath = if ($ContractPath) { (Resolve-Path $ContractPath).Path } else { "" }
	allowedPaths = $normalizedAllowedPaths
	changedFiles = $changedFileArray
	scopeOk = $scopeOk
	scopeViolations = $scopeViolationArray
	commands = $commandArray
	commandsOk = $commandsOk
}

if ($Json) {
	$result | ConvertTo-Json -Depth 8
} elseif ($SummaryOnly) {
	Write-Host "status: $($result.status)"
	Write-Host "scope:  $(if ($result.scopeOk) { 'ok' } else { 'failed' })"
	Write-Host "cmds:   $(if ($result.commandsOk) { 'ok' } else { 'failed' })"
} else {
	Write-Host "Local agent run check"
	Write-Host "  status:        $($result.status)"
	Write-Host "  repo:          $($result.repoRoot)"
	Write-Host "  changed files: $($result.changedFiles.Count)"
	if ($AllowedPath.Count -gt 0) {
		Write-Host "  allowed:       $($normalizedAllowedPaths -join ', ')"
	}
	if (!$result.scopeOk) {
		Write-Host "  scope issues:  $($result.scopeViolations -join ', ')"
	}
	foreach ($command in $commands) {
		Write-Host "  command:       $($command.cmd) => $($command.status)"
	}
}

if ($status -ne "verified") {
	exit 1
}
