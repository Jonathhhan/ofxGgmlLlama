param(
	[Parameter(Position = 0)]
	[ValidateSet("text", "chat", "embedding", "emb", "codex")]
	[string]$Example = "text",
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[int]$Jobs = 1,
	[switch]$Clean
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$buildScript = Join-Path $scriptRoot "dev\build-simple-example.ps1"

$exampleName = switch ($Example) {
	"text" { "ofxGgmlTextExample" }
	"chat" { "ofxGgmlChatExample" }
	"embedding" { "ofxGgmlEmbeddingExample" }
	"emb" { "ofxGgmlEmbeddingExample" }
	"codex" { "ofxGgmlLlamaCodexLocalExample" }
}

$arguments = @{
	Configuration = $Configuration
	Platform = $Platform
	Example = $exampleName
	Jobs = $Jobs
}
if ($Clean) {
	$arguments.Clean = $true
}

& $buildScript @arguments
exit $LASTEXITCODE
