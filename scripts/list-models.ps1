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
	if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
	if ($Bytes -ge 1MB) { return "{0:N1} MB" -f ($Bytes / 1MB) }
	if ($Bytes -ge 1KB) { return "{0:N1} KB" -f ($Bytes / 1KB) }
	return "$Bytes B"
}

function Get-ModelRoleHint {
	param([string]$Name)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "embed|embedding|bge|e5|gte|nomic|jina") { return "embedding" }
	return "text"
}

function Get-TinyModelHint {
	param([string]$Name, [long]$Bytes)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "tiny|smoke|test|mini|0\.5b|0_5b|1\.5b|1_5b") { return $true }
	return $Bytes -gt 0 -and $Bytes -le 2GB
}

function Get-ModelFamily {
	param([string]$Name)
	$lower = $Name.ToLowerInvariant()
	if ($lower -match "qwen3") { return "Qwen3" }
	if ($lower -match "qwen2\.5-coder") { return "Qwen2.5-Coder" }
	if ($lower -match "qwen2\.5") { return "Qwen2.5" }
	if ($lower -match "glm-") { return "GLM" }
	if ($lower -match "llama3|llama-3") { return "Llama3" }
	if ($lower -match "mistral") { return "Mistral" }
	if ($lower -match "mixtral") { return "Mixtral" }
	if ($lower -match "phi3|phi-3") { return "Phi3" }
	if ($lower -match "bge") { return "BGE" }
	if ($lower -match "nomic") { return "Nomic" }
	if ($lower -match "gemma") { return "Gemma" }
	if ($lower -match "deepseek") { return "DeepSeek" }
	if ($lower -match "codex") { return "Codex-Distill" }
	return "unknown"
}

function Get-QuantizationHint {
	param([string]$Name)
	$upper = $Name.ToUpperInvariant()
	if ($upper -match "Q6_K_XL") { return "Q6_K_XL" }
	if ($upper -match "Q6_K") { return "Q6_K" }
	if ($upper -match "Q5_K_S") { return "Q5_K_S" }
	if ($upper -match "Q5_K_M") { return "Q5_K_M" }
	if ($upper -match "Q5_0") { return "Q5_0" }
	if ($upper -match "Q4_K_XL") { return "Q4_K_XL" }
	if ($upper -match "Q4_K_S") { return "Q4_K_S" }
	if ($upper -match "Q4_K_M") { return "Q4_K_M" }
	if ($upper -match "Q4_0") { return "Q4_0" }
	if ($upper -match "Q8_0") { return "Q8_0" }
	if ($upper -match "IQ4_XS") { return "IQ4_XS" }
	if ($upper -match "IQ3_XXS") { return "IQ3_XXS" }
	if ($upper -match "IQ2_XXS") { return "IQ2_XXS" }
	if ($upper -match "QQ4_0") { return "QQ4_0" }
	return "unknown"
}

function Get-ParameterHint {
	param([string]$Name)
	$lower = $Name.ToLowerInvariant()
	$match = [regex]::Match($lower, '(\d+\.?\d*)b[_-]')
	if ($match.Success) { return $match.Groups[1].Value }
	$match = [regex]::Match($lower, '(\d+\.?\d*)b$')
	if ($match.Success) { return $match.Groups[1].Value }
	return ""
}

function Get-LlamaCompatHint {
	param([string]$Family, [string]$Quant)
	if ($family -eq "unknown") { return "unverified family" }
	if ($quant -eq "unknown") { return "unknown quantization" }
	$knownQuants = @("Q4_0","Q4_K_S","Q4_K_XL","Q4_K_M","Q5_0","Q5_K_S","Q5_K_M","Q6_K","Q6_K_XL","Q8_0","IQ4_XS","IQ3_XXS","IQ2_XXS","QQ4_0")
	if ($knownQuants -contains $quant) { return "compatible" }
	return "non-standard quant"
}

$directories = Get-OfxGgmlUniqueDirectories (Get-OfxGgmlModelSearchDirectories `
	-AddonRoot $addonRoot `
	-ExampleRoot (Join-Path $addonRoot "ofxGgmlTextExample") `
	-ExtraExampleNames @("ofxGgmlChatExample", "ofxGgmlEmbeddingExample"))

$models = New-Object System.Collections.Generic.List[object]
foreach ($modelFile in (Get-OfxGgmlModelFiles $directories)) {
	$name = $modelFile.Name
	$family = Get-ModelFamily $name
	$quant = Get-QuantizationHint $name
	$params = Get-ParameterHint $name
	$compat = Get-LlamaCompatHint $family $quant
	$models.Add([pscustomobject]@{
		Name = $name
		Path = $modelFile.FullName
		Directory = $modelFile.DirectoryName
		Bytes = [long]$modelFile.Length
		Size = Format-Size $modelFile.Length
		RoleHint = Get-ModelRoleHint $name
		TinyCandidate = Get-TinyModelHint -Name $name -Bytes ([long]$modelFile.Length)
		Family = $family
		Quantization = $quant
		Parameters = $params
		LlamaCompat = $compat
	})
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
	if (!$SummaryOnly) { $result.Models = $modelArray }
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
			$compatMark = switch ($model.LlamaCompat) {
				"compatible" { "" }
				"unknown quantization" { " ?quant" }
				"unverified family" { " ?family" }
				"non-standard quant" { " !quant" }
				default { "" }
			}
			Write-Host ("  {0,-9} {1,-4} {2,-8} {3,-10} {4,-7} {5}{6}" -f `
				$model.RoleHint, $tiny, $model.Quantization, $model.Family, $model.Size, $model.Name, $compatMark)
		}
	}
}

if ($Strict -and $models.Count -eq 0) { exit 1 }
