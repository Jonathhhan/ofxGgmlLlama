param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Split-Path -Parent $scriptRoot
$ofRoot = Split-Path -Parent (Split-Path -Parent $addonRoot)
$exampleName = "ofxGgmlChatExample"
$exampleDir = Join-Path $addonRoot $exampleName
$buildScript = Join-Path $scriptRoot "build-example.ps1"

function Find-ProjectGenerator {
	$candidates = @(
		(Join-Path $ofRoot "projectGenerator\resources\app\app\projectGenerator.exe"),
		(Join-Path $ofRoot "projectGenerator\projectGenerator.exe"),
		(Join-Path $ofRoot "projectGenerator-jan2026\resources\app\app\projectGenerator.exe"),
		(Join-Path $ofRoot "projectGenerator-jan2026\projectGenerator.exe")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	return ""
}

function Ensure-GeneratedProject {
	if ($IsLinux -or $IsMacOS) {
		return
	}
	$project = Join-Path $exampleDir "$exampleName.vcxproj"
	if (Test-Path -LiteralPath $project -PathType Leaf) {
		return
	}
	$projectGenerator = Find-ProjectGenerator
	if ([string]::IsNullOrWhiteSpace($projectGenerator)) {
		throw "Visual Studio project not found and projectGenerator.exe was not found under $ofRoot."
	}
	Write-Host "==> Generating $exampleName Visual Studio project"
	& $projectGenerator "-o$ofRoot" "-aofxGgmlCore,ofxGgmlLlama,ofxImGui" "-pvs" $exampleDir
	if ($LASTEXITCODE -ne 0) {
		throw "projectGenerator failed with exit code $LASTEXITCODE"
	}
}

Ensure-GeneratedProject

if ($Clean) {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "chat" `
		-Clean
} else {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "chat"
}
exit $LASTEXITCODE
