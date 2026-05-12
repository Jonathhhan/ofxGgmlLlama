param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$buildScript = Join-Path $scriptRoot "build-example.ps1"

if ($Clean) {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "embedding" `
		-Clean
} else {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "embedding"
}
exit $LASTEXITCODE
