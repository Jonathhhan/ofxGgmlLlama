param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Invoke-GitLines {
	param([string[]]$Arguments)
	$output = & git @Arguments 2>&1
	if ($LASTEXITCODE -ne 0) {
		throw "git $($Arguments -join ' ') failed: $($output -join "`n")"
	}
	return @($output | ForEach-Object { $_.ToString() })
}

function Assert-NoMatches {
	param(
		[string[]]$Paths,
		[string[]]$Patterns,
		[string]$Label
	)
	$matches = New-Object System.Collections.Generic.List[string]
	foreach ($path in $Paths) {
		$normalized = $path -replace "\\", "/"
		foreach ($pattern in $Patterns) {
			if ($normalized -match $pattern) {
				$matches.Add($path)
				break
			}
		}
	}
	if ($matches.Count -gt 0) {
		throw "$Label contains generated artifacts:`n$($matches -join "`n")"
	}
}

function Assert-Ignored {
	param([string[]]$Paths)
	foreach ($path in $Paths) {
		$output = & git check-ignore --quiet -- $path
		if ($LASTEXITCODE -ne 0) {
			throw "Expected generated artifact path to be ignored: $path"
		}
	}
}

$null = $Configuration
$null = $Platform

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
Push-Location $repoRoot
try {
	$forbiddenPatterns = @(
		"^\.vs/",
		"(^|/)build/",
		"(^|/)obj/",
		"^libs/llama\.cpp/\.source/",
		"^libs/llama\.cpp/build",
		"(^|/)(models)(/|$)",
		"\.(exe|dll|exp|ilk|lib|pdb|sln|suo|user|vcxproj|vcxproj\.filters|VC\.db|VC\.VC\.opendb)$",
		"\.(gguf|safetensors|onnx|pt|pth|ckpt)$"
	)

	Write-Step "Checking tracked generated artifacts"
	$tracked = Invoke-GitLines @("ls-files")
	Assert-NoMatches -Paths $tracked -Patterns $forbiddenPatterns -Label "Tracked files"

	Write-Step "Checking staged generated artifacts"
	$staged = Invoke-GitLines @("diff", "--cached", "--name-only")
	Assert-NoMatches -Paths $staged -Patterns $forbiddenPatterns -Label "Staged files"

	Write-Step "Checking generated artifact ignore rules"
	Assert-Ignored @(
		"build/artifact.tmp",
		"libs/llama.cpp/.source/CMakeLists.txt",
		"libs/llama.cpp/build/CMakeCache.txt",
		"libs/llama/bin/llama-server.exe",
		"models/model.gguf",
		"ofxGgmlTextExample/ofxGgmlTextExample.vcxproj",
		"ofxGgmlTextExample/bin/ofxGgmlTextExample.exe"
	)
} finally {
	Pop-Location
}

Write-Step "Artifact hygiene checks passed"
