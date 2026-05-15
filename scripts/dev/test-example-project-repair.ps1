param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Assert-IncludeDirectory {
	param(
		[string]$Project,
		[string]$IncludeDirectory
	)
	[xml]$doc = Get-Content -LiteralPath $Project -Raw
	$namespace = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
	$namespace.AddNamespace("msb", "http://schemas.microsoft.com/developer/msbuild/2003")
	$nodes = @($doc.SelectNodes("//msb:AdditionalIncludeDirectories", $namespace))
	foreach ($node in $nodes) {
		$parts = @($node.InnerText -split ";" | Where-Object { $_ })
		if ($parts -contains $IncludeDirectory) {
			return
		}
	}
	throw "$Project is missing include directory: $IncludeDirectory"
}

function Assert-GuardedPostBuild {
	param([string]$Project)
	[xml]$doc = Get-Content -LiteralPath $Project -Raw
	$namespace = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
	$namespace.AddNamespace("msb", "http://schemas.microsoft.com/developer/msbuild/2003")
	$nodes = @($doc.SelectNodes("//msb:PostBuildEvent/msb:Command", $namespace))
	foreach ($node in $nodes) {
		if ($node.InnerText -match 'xcopy\s+/Y\s+/E' -and
			$node.InnerText -notmatch '^\s*if exist ') {
			throw "$Project has an unguarded DLL post-build copy command."
		}
	}
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$examples = @("ofxGgmlTextExample", "ofxGgmlChatExample", "ofxGgmlEmbeddingExample", "ofxGgmlLlamaCodexLocalExample")

foreach ($example in $examples) {
	Write-Step "Repairing $example generated metadata"
	& (Join-Path $scriptRoot "dev\build-simple-example.ps1") `
		-Example $example `
		-Configuration $Configuration `
		-Platform $Platform `
		-RepairOnly
	if (!$?) {
		throw "$example project repair failed"
	}
	$project = Join-Path $addonRoot "$example\$example.vcxproj"
	Assert-IncludeDirectory -Project $project -IncludeDirectory "..\src"
	Assert-IncludeDirectory -Project $project -IncludeDirectory "..\..\ofxGgmlCore\src"
	Assert-GuardedPostBuild -Project $project
}

Write-Step "Example project repair coverage passed"
