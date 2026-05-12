param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $scriptRoot "build-simple-example.ps1"

if ($Clean) {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "example-text" `
		-Clean
} else {
	& $buildScript `
		-Configuration $Configuration `
		-Platform $Platform `
		-Example "example-text"
}
exit $LASTEXITCODE
