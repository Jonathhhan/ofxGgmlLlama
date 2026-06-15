param(
	[switch]$Json,
	[switch]$SummaryOnly,
	[switch]$Strict
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
. (Join-Path $scriptRoot "ofxGgml-launch-utils.ps1")

function Format-Size {
	param([long]$Bytes)
	if ($Bytes -ge 1GB) {
		return "{0:N2} GB" -f ($Bytes / 1GB)
	}
	if ($Bytes -ge 1MB) {
		return "{0:N1} MB" -f ($Bytes / 1MB)
	}
	if ($Bytes -ge 1KB) {
		return "{0:N1} KB" -f ($Bytes / 1KB)
	}
	return "$Bytes B"
}

function Get-ModelRoleHint {
	param([string]$Name)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "embed|embedding|bge|e5|gte|nomic|jina") {
		return "embedding"
	}
	return "text"
}

function Get-TinyModelHint {
	param(
		[string]$Name,
		[long]$Bytes
	)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "tiny|smoke|test|mini|0\.5b|0_5b|1\.5b|1_5b") {
		return $true
	}
	return $Bytes -gt 0 -and $Bytes -le 2GB
}

function Get-UniqueDirectories {
	param([string[]]$Directories)
	$seen = @{}
	foreach ($directory in $Directories) {
		if ([string]::IsNullOrWhiteSpace($directory)) {
			continue
		}
		$fullPath = [System.IO.Path]::GetFullPath($directory)
		$key = $fullPath.ToLowerInvariant()
		if (!$seen.ContainsKey($key)) {
			$seen[$key] = $true
			$fullPath
		}
	}
}

$directories = Get-UniqueDirectories (Get-OfxGgmlModelSearchDirectories `
	-AddonRoot $addonRoot `
	-ExampleRoot (Join-Path $addonRoot "ofxGgmlTextExample") `
	-ExtraExampleNames @(
		"ofxGgmlChatExample",
		"ofxGgmlEmbeddingExample"))

$models = New-Object System.Collections.Generic.List[object]
foreach ($directory in $directories) {
	if (!(Test-Path -LiteralPath $directory -PathType Container)) {
		continue
	}
	Get-ChildItem -LiteralPath $directory -Filter "*.gguf" -File -ErrorAction SilentlyContinue |
		Sort-Object Name |
		ForEach-Object {
			$models.Add([pscustomobject]@{
				Name = $_.Name
				Path = $_.FullName
				Directory = $directory
				Bytes = [long]$_.Length
				Size = Format-Size $_.Length
				RoleHint = Get-ModelRoleHint $_.Name
				TinyCandidate = Get-TinyModelHint -Name $_.Name -Bytes ([long]$_.Length)
			})
		}
}

if ($Json) {
	$modelArray = @($models | ForEach-Object { $_ })
	$textModels = @($modelArray | Where-Object { $_.RoleHint -eq "text" })
	$embeddingModels = @($modelArray | Where-Object { $_.RoleHint -eq "embedding" })
	$tinyTextModels = @($textModels | Where-Object { $_.TinyCandidate })
	$result = [ordered]@{
		Root = $addonRoot.Path
		SummaryOnly = [bool]$SummaryOnly
		Summary = [pscustomobject]@{
			SearchDirectoryCount = @($directories).Count
			ExistingSearchDirectoryCount = @($directories | Where-Object { Test-Path -LiteralPath $_ -PathType Container }).Count
			ModelCount = @($modelArray).Count
			TextModelCount = @($textModels).Count
			EmbeddingModelCount = @($embeddingModels).Count
			TinyTextModelCount = @($tinyTextModels).Count
			HasTinyTextModel = @($tinyTextModels).Count -gt 0
			FirstTinyTextModel = if (@($tinyTextModels).Count -gt 0) { [string]@($tinyTextModels)[0].Path } else { "" }
		}
		SearchDirectories = @($directories)
	}
	if (!$SummaryOnly) {
		$result.Models = $modelArray
	}
	[pscustomobject]$result | ConvertTo-Json -Depth 5
} else {
	Write-Host "ofxGgmlLlama model search"
	Write-Host "Root  $addonRoot"
	Write-Host ""
	Write-Host "Search directories:"
	foreach ($directory in $directories) {
		$exists = Test-Path -LiteralPath $directory -PathType Container
		Write-Host ("  [{0}] {1}" -f ($(if ($exists) { "x" } else { " " }), $directory))
	}
	Write-Host ""
	if ($models.Count -eq 0) {
		Write-Host "No GGUF models found."
		Write-Host "Put models under addons\models or ofxGgmlLlama\models, or pass -Model to the run scripts."
	} else {
		Write-Host "Models:"
		foreach ($model in $models) {
			$tiny = if ($model.TinyCandidate) { "tiny" } else { "full" }
			Write-Host ("  {0}  {1}  {2}  {3}" -f $model.RoleHint.PadRight(9), $tiny.PadRight(4), $model.Size.PadLeft(9), $model.Path)
		}
	}
}

if ($Strict -and $models.Count -eq 0) {
	exit 1
}
