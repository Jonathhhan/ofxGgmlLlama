param(
	[string]$Configuration = "Release",
	[string]$Platform = "x64",
	[string]$Example = "ofxGgmlTextExample",
	[int]$Jobs = 1,
	[switch]$Clean,
	[switch]$RepairOnly
)

$ErrorActionPreference = "Stop"

function Write-Step {
	param([string]$Message)
	Write-Host "==> $Message"
}

function Test-WindowsHost {
	return !($IsLinux -or $IsMacOS)
}

function Normalize-WindowsPathEnvironment {
	if (!(Test-WindowsHost)) {
		return
	}
	$variables = [Environment]::GetEnvironmentVariables("Process")
	$pathNames = New-Object System.Collections.Generic.List[string]
	foreach ($key in $variables.Keys) {
		$name = [string]$key
		if ($name.Equals("Path", [System.StringComparison]::OrdinalIgnoreCase)) {
			$pathNames.Add($name)
		}
	}
	if ($pathNames.Count -le 1) {
		return
	}

	$preferredName = if ($pathNames.Contains("Path")) { "Path" } else { $pathNames[0] }
	$pathValue = [string]$variables[$preferredName]
	if ([string]::IsNullOrWhiteSpace($pathValue)) {
		foreach ($name in $pathNames) {
			$value = [string]$variables[$name]
			if (![string]::IsNullOrWhiteSpace($value)) {
				$pathValue = $value
				break
			}
		}
	}
	foreach ($name in $pathNames) {
		if (!$name.Equals("Path", [System.StringComparison]::Ordinal)) {
			[Environment]::SetEnvironmentVariable($name, $null, "Process")
		}
	}
	[Environment]::SetEnvironmentVariable("Path", $pathValue, "Process")
}

function Test-ExampleUsesAddon {
	param(
		[string]$ExampleDir,
		[string]$AddonName
	)
	$addonsMake = Join-Path $ExampleDir "addons.make"
	if (!(Test-Path -LiteralPath $addonsMake)) {
		return $false
	}
	return @(
		Get-Content -LiteralPath $addonsMake |
			ForEach-Object { $_.Trim() } |
			Where-Object { $_ -eq $AddonName }
	).Count -gt 0
}

function Invoke-CheckedNative {
	param(
		[string]$Step,
		[scriptblock]$Command
	)
	& $Command
	if ($LASTEXITCODE -ne 0) {
		throw "$Step failed with exit code $LASTEXITCODE"
	}
}

function Get-StableNameFragment {
	param([string]$Text)
	$sha1 = [System.Security.Cryptography.SHA1]::Create()
	try {
		$bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
		$hash = $sha1.ComputeHash($bytes)
		return [System.BitConverter]::ToString($hash).Replace("-", "")
	} finally {
		$sha1.Dispose()
	}
}

function Invoke-WithNamedMutex {
	param(
		[string]$Name,
		[scriptblock]$Command
	)
	$mutex = New-Object System.Threading.Mutex($false, $Name)
	$locked = $false
	try {
		$locked = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
		if (!$locked) {
			throw "Timed out waiting for build lock: $Name"
		}
		& $Command
	} finally {
		if ($locked) {
			$mutex.ReleaseMutex()
		}
		$mutex.Dispose()
	}
}

function Get-MsBuild {
	$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path -LiteralPath $vswhere) {
		$installPath = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null
		if ($installPath) {
			$candidate = Join-Path $installPath "MSBuild\Current\Bin\MSBuild.exe"
			if (Test-Path -LiteralPath $candidate) {
				return $candidate
			}
		}
	}

	foreach ($version in @("18", "17", "16")) {
		foreach ($edition in @("Community", "Professional", "Enterprise", "BuildTools")) {
			$candidate = "C:\Program Files\Microsoft Visual Studio\$version\$edition\MSBuild\Current\Bin\MSBuild.exe"
			if (Test-Path -LiteralPath $candidate) {
				return $candidate
			}
		}
	}
	return ""
}

function Resolve-BuildJobs {
	param([int]$RequestedJobs)
	if ($RequestedJobs -lt 0) {
		throw "-Jobs must be 0 or greater."
	}
	if ($RequestedJobs -eq 0) {
		return [Environment]::ProcessorCount
	}
	return $RequestedJobs
}

function Get-MsBuildParallelArguments {
	param([int]$BuildJobs)
	if ($BuildJobs -gt 1) {
		return @("/p:MultiProcessorCompilation=true", "/m:$BuildJobs")
	}
	return @("/p:MultiProcessorCompilation=false", "/m:1")
}

function Find-ProjectGenerator {
	param([string]$OfRoot)
	$candidates = @(
		(Join-Path $OfRoot "projectGenerator\resources\app\app\projectGenerator.exe"),
		(Join-Path $OfRoot "projectGenerator\projectGenerator.exe"),
		(Join-Path $OfRoot "projectGenerator-jan2026\resources\app\app\projectGenerator.exe"),
		(Join-Path $OfRoot "projectGenerator-jan2026\projectGenerator.exe")
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}
	return ""
}

function Ensure-GeneratedVisualStudioProject {
	param(
		[string]$ExampleName,
		[string]$ExamplePath,
		[string]$OfRoot
	)
	if (!(Test-WindowsHost)) {
		return
	}
	$project = Join-Path $ExamplePath "$ExampleName.vcxproj"
	if (Test-Path -LiteralPath $project -PathType Leaf) {
		return
	}

	$templateRoot = Join-Path $OfRoot "scripts\templates\winvs"
	$templateProject = Join-Path $templateRoot "emptyExample.vcxproj"
	if (!(Test-Path -LiteralPath $templateProject -PathType Leaf)) {
		throw "Visual Studio project not found and openFrameworks winvs template is missing: $templateProject"
	}
	$copies = @(
		@{ Source = "emptyExample.vcxproj"; Target = "$ExampleName.vcxproj" },
		@{ Source = "emptyExample.vcxproj.filters"; Target = "$ExampleName.vcxproj.filters" },
		@{ Source = "emptyExample.vcxproj.user"; Target = "$ExampleName.vcxproj.user" },
		@{ Source = "emptyExample.sln"; Target = "$ExampleName.sln" },
		@{ Source = "icon.rc"; Target = "icon.rc" }
	)
	foreach ($copy in $copies) {
		$source = Join-Path $templateRoot $copy.Source
		$target = Join-Path $ExamplePath $copy.Target
		if (!(Test-Path -LiteralPath $source -PathType Leaf)) {
			continue
		}
		$text = Get-Content -LiteralPath $source -Raw
		$text = $text.Replace("emptyExample", $ExampleName)
		Set-Content -LiteralPath $target -Value $text -NoNewline
	}
	Write-Step "Initialized generated Visual Studio project metadata from openFrameworks template"
}

function Test-GeneratedAddonPath {
	param([string]$Path)
	if ([string]::IsNullOrWhiteSpace($Path)) {
		return $false
	}

	$normalized = $Path -replace "/", "\"
	return ($normalized -match '(^|\\)libs\\ggml\\\.source(\\|$)') -or
		($normalized -match '(^|\\)libs\\ggml\\build[^\\]*(\\|$)') -or
		($normalized -match '(^|\\)libs\\llama\.cpp\\\.source(\\|$)') -or
		($normalized -match '(^|\\)libs\\llama\.cpp\\build[^\\]*(\\|$)') -or
		($normalized -match '(^|\\)libs\\sam3\.cpp\\build[^\\]*(\\|$)') -or
		($normalized -match '(^|\\)libs\\sam3\.cpp\\(ggml|examples|media|scripts|tests)(\\|$)') -or
		($normalized -match '(^|\\)libs\\sam3\.cpp\\sam3\.cpp$')
}

function Get-RelativeProjectPath {
	param(
		[string]$ProjectDir,
		[string]$FilePath
	)
	$projectUri = [System.Uri]((Resolve-Path -LiteralPath $ProjectDir).Path.TrimEnd("\") + "\")
	$fileUri = [System.Uri](Resolve-Path -LiteralPath $FilePath).Path
	return [System.Uri]::UnescapeDataString(
		$projectUri.MakeRelativeUri($fileUri).ToString()).Replace("/", "\")
}

function Get-FirstItemGroup {
	param(
		[xml]$Doc,
		[System.Xml.XmlNamespaceManager]$Namespace,
		[string]$PreferredTag
	)
	$itemGroups = @($Doc.SelectNodes("//msb:ItemGroup", $Namespace))
	foreach ($group in $itemGroups) {
		if ($group.SelectSingleNode("msb:$PreferredTag", $Namespace)) {
			return $group
		}
	}
	if ($itemGroups.Count -gt 0) {
		return $itemGroups[0]
	}
	return $null
}

function Add-VisualStudioProjectItem {
	param(
		[xml]$Doc,
		[System.Xml.XmlNamespaceManager]$Namespace,
		[string]$Tag,
		[string]$Include,
		[string]$Filter = ""
	)
	$normalizedInclude = ($Include -replace "/", "\")
	$existingNodes = @($Doc.SelectNodes("//msb:$Tag[@Include]", $Namespace))
	foreach ($existing in $existingNodes) {
		if (([string]$existing.Include -replace "/", "\").Equals(
			$normalizedInclude,
			[System.StringComparison]::OrdinalIgnoreCase)) {
			return $false
		}
	}
	$itemGroup = Get-FirstItemGroup -Doc $Doc -Namespace $Namespace -PreferredTag $Tag
	if (!$itemGroup) {
		return $false
	}
	$item = $Doc.CreateElement($Tag, $Doc.DocumentElement.NamespaceURI)
	$item.SetAttribute("Include", $Include)
	if (![string]::IsNullOrWhiteSpace($Filter)) {
		$filterNode = $Doc.CreateElement("Filter", $Doc.DocumentElement.NamespaceURI)
		$filterNode.InnerText = $Filter
		[void]$item.AppendChild($filterNode)
	}
	[void]$itemGroup.AppendChild($item)
	return $true
}

function Repair-VisualStudioAddonItems {
	param(
		[xml]$Doc,
		[System.Xml.XmlNamespaceManager]$Namespace,
		[string]$Path
	)
	$changed = $false
	$projectDir = Split-Path -Parent $Path
	$isFilters = $Path.EndsWith(".vcxproj.filters", [System.StringComparison]::OrdinalIgnoreCase)
	if (!$Path.EndsWith(".vcxproj", [System.StringComparison]::OrdinalIgnoreCase) -and !$isFilters) {
		return $false
	}

	$addonsRoot = Split-Path -Parent $addonRoot.Path
	$coreRoot = Join-Path $addonsRoot "ofxGgmlCore"
	$addonEntries = @()
	if (Test-Path -LiteralPath $coreRoot) {
		$addonEntries += @{
			Name = "ofxGgmlCore"
			Root = $coreRoot
			SourceRoots = @("src")
			Excludes = @()
		}
	}
	$addonEntries += @{
		Name = "ofxGgmlLlama"
		Root = $addonRoot.Path
		SourceRoots = @("src")
		Excludes = @()
	}
	$imguiRoot = Join-Path $addonsRoot "ofxImGui"
	if ((Test-ExampleUsesAddon -ExampleDir $exampleDir -AddonName "ofxImGui") -and
		(Test-Path -LiteralPath $imguiRoot)) {
		$addonEntries += @{
			Name = "ofxImGui"
			Root = $imguiRoot
			SourceRoots = @(
				"src",
				"libs\imgui\src",
				"libs\imgui\backends",
				"libs\imgui\extras"
			)
			Excludes = @("src\EngineVk.cpp")
		}
	}

	foreach ($entry in $addonEntries) {
		$sourceFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
		$headerFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
		foreach ($sourceRootName in $entry.SourceRoots) {
			$sourceRoot = Join-Path $entry.Root $sourceRootName
			if (!(Test-Path -LiteralPath $sourceRoot)) {
				continue
			}
			Get-ChildItem -LiteralPath $sourceRoot -Recurse -File | ForEach-Object {
				$relativeToAddon = Get-RelativeProjectPath -ProjectDir $entry.Root -FilePath $_.FullName
				if ($entry.Excludes -notcontains $relativeToAddon) {
					if ($_.Extension -in @(".cpp", ".cxx", ".cc")) {
						$sourceFiles.Add($_)
					} elseif ($_.Extension -in @(".h", ".hpp")) {
						$headerFiles.Add($_)
					}
				}
			}
		}
		foreach ($file in $sourceFiles) {
			$relative = Get-RelativeProjectPath -ProjectDir $projectDir -FilePath $file.FullName
			$filter = if ($isFilters) {
				("addons\" + $entry.Name + "\" + (Split-Path -Parent $relative).TrimStart(".\").Replace("..\", ""))
			} else { "" }
			if (Add-VisualStudioProjectItem -Doc $Doc -Namespace $Namespace -Tag "ClCompile" -Include $relative -Filter $filter) {
				$changed = $true
			}
		}
		foreach ($file in $headerFiles) {
			$relative = Get-RelativeProjectPath -ProjectDir $projectDir -FilePath $file.FullName
			$filter = if ($isFilters) {
				("addons\" + $entry.Name + "\" + (Split-Path -Parent $relative).TrimStart(".\").Replace("..\", ""))
			} else { "" }
			if (Add-VisualStudioProjectItem -Doc $Doc -Namespace $Namespace -Tag "ClInclude" -Include $relative -Filter $filter) {
				$changed = $true
			}
		}
	}
	return $changed
}

function Repair-VisualStudioProjectFile {
	param(
		[string]$Path,
		[string[]]$AddonDefines = @(),
		[string[]]$AddonIncludeDirs = @()
	)
	if (!(Test-Path -LiteralPath $Path)) {
		return
	}

	[xml]$doc = Get-Content -LiteralPath $Path -Raw
	$namespace = New-Object System.Xml.XmlNamespaceManager($doc.NameTable)
	$namespace.AddNamespace("msb", "http://schemas.microsoft.com/developer/msbuild/2003")
	$changed = $false

	foreach ($tag in @("ClCompile", "ClInclude", "None", "CustomBuild", "CudaCompile", "Filter")) {
		$nodes = @($doc.SelectNodes("//msb:$tag[@Include]", $namespace))
		$seenIncludes = @{}
		foreach ($node in $nodes) {
			$normalizedInclude = ([string]$node.Include -replace "/", "\")
			$extension = [System.IO.Path]::GetExtension($normalizedInclude)
			$headerCompiledAsSource = $tag -eq "ClCompile" -and $extension -in @(".h", ".hpp")
			$duplicateInclude = $seenIncludes.ContainsKey($normalizedInclude.ToLowerInvariant())
			if ((Test-GeneratedAddonPath $node.Include) -or $headerCompiledAsSource -or $duplicateInclude) {
				[void]$node.ParentNode.RemoveChild($node)
				$changed = $true
			} else {
				$seenIncludes[$normalizedInclude.ToLowerInvariant()] = $true
			}
		}
	}

	$includeNodes = @($doc.SelectNodes("//msb:AdditionalIncludeDirectories", $namespace))
	foreach ($node in $includeNodes) {
		$parts = @($node.InnerText -split ";" | Where-Object { $_ -and !(Test-GeneratedAddonPath $_) })
		if ($Path.EndsWith(".vcxproj", [System.StringComparison]::OrdinalIgnoreCase)) {
			foreach ($includeDir in $AddonIncludeDirs) {
				if ($parts -notcontains $includeDir) {
					$parts += $includeDir
					$changed = $true
				}
			}
		}
		$updated = $parts -join ";"
		if ($updated -ne $node.InnerText) {
			$node.InnerText = $updated
			$changed = $true
		}
	}

	if ($AddonDefines.Count -gt 0 -and $Path.EndsWith(".vcxproj", [System.StringComparison]::OrdinalIgnoreCase)) {
		$optionNodes = @($doc.SelectNodes("//msb:ClCompile/msb:AdditionalOptions", $namespace))
		foreach ($node in $optionNodes) {
			$options = @($node.InnerText -split "\s+" | Where-Object { $_ })
			foreach ($define in $AddonDefines) {
				$option = "-D$define"
				if ($options -notcontains $option) {
					$options += $option
					$changed = $true
				}
			}
			$valuedDefines = @{}
			foreach ($option in $options) {
				if ($option -match '^-D([^=\s]+)=') {
					$valuedDefines[$matches[1]] = $true
				}
			}
			$cleanOptions = @($options | Where-Object {
				!($_ -match '^-D([^=\s]+)$' -and $valuedDefines.ContainsKey($matches[1]))
			})
			$staleOptions = @(
				"OFXIMGUI_DEBUG",
				"IMGUI_IMPL_OPENGL_ES2",
				"IMGUI_IMPL_OPENGL_ES3",
				"USE_PI_LEGACY"
			)
			$cleanOptions = @($cleanOptions | Where-Object {
				!($_ -match '^-D([^=\s]+)(?:=.*)?$' -and
					$staleOptions -contains $matches[1] -and
					$AddonDefines -notcontains $matches[1])
			})
			if ($cleanOptions.Count -ne $options.Count) {
				$changed = $true
			}
			$node.InnerText = ($cleanOptions -join " ")
		}
	}

	if (Repair-VisualStudioAddonItems -Doc $doc -Namespace $namespace -Path $Path) {
		$changed = $true
	}

	foreach ($node in @($doc.SelectNodes("//msb:PostBuildEvent/msb:Command", $namespace))) {
		if ($node.InnerText -match '\$\(ProjectDir\)dll\\([^\\]+)\\\*\.dll') {
			$platformName = $matches[1]
			$guardedCommand = "if exist `"`$(ProjectDir)dll\$platformName\*.dll`" xcopy /Y /E `"`$(ProjectDir)dll\$platformName\*.dll`" `"`$(TargetDir)`""
			if ($node.InnerText -ne $guardedCommand) {
				$node.InnerText = $guardedCommand
				$changed = $true
			}
		}
	}

	if ($changed) {
		$doc.Save($Path)
		Write-Step "Updated generated project metadata in $(Split-Path -Leaf $Path)"
	}
}

function Get-AddonDefines {
	$defines = New-Object System.Collections.Generic.List[string]
	$configPaths = New-Object System.Collections.Generic.List[string]
	$configPaths.Add((Join-Path $addonRoot "addon_config.mk"))
	$imguiRoot = Join-Path (Split-Path -Parent $addonRoot.Path) "ofxImGui"
	if ((Test-ExampleUsesAddon -ExampleDir $exampleDir -AddonName "ofxImGui") -and
		(Test-Path -LiteralPath $imguiRoot)) {
		$configPaths.Add((Join-Path $imguiRoot "addon_config.mk"))
	}
	foreach ($configPath in $configPaths) {
		if (!(Test-Path -LiteralPath $configPath)) {
			continue
		}
		$section = ""
		Get-Content -LiteralPath $configPath | ForEach-Object {
			if ($_ -match '^([A-Za-z0-9_/]+):\s*$') {
				$section = $matches[1]
			}
			if (($section -eq "common" -or $section -eq "vs") -and
				$_ -match 'ADDON_CFLAGS\s*(?:\+)?=\s*-D([A-Za-z0-9_]+(?:=[^\s]+)?)') {
				if (!$defines.Contains($matches[1])) {
					$defines.Add($matches[1])
				}
			}
		}
	}
	return @($defines)
}

function Get-AddonIncludeDirectories {
	$includeDirs = New-Object System.Collections.Generic.List[string]
	foreach ($path in @(
		"..\src",
		"..\..\ofxGgmlCore\src"
	)) {
		$includeDirs.Add($path)
	}
	if (Test-ExampleUsesAddon -ExampleDir $exampleDir -AddonName "ofxImGui") {
		foreach ($path in @(
			"..\..\ofxImGui\src",
			"..\..\ofxImGui\libs\imgui",
			"..\..\ofxImGui\libs\imgui\src",
			"..\..\ofxImGui\libs\imgui\backends",
			"..\..\ofxImGui\libs\imgui\extras"
		)) {
			$includeDirs.Add($path)
		}
	}
	return @($includeDirs)
}

$scriptRoot = Resolve-Path (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..")
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")
$ofRoot = Split-Path -Parent (Split-Path -Parent $addonRoot)
$exampleDir = Join-Path $addonRoot $Example
if (!(Test-Path -LiteralPath $exampleDir)) {
	throw "Example directory not found: $exampleDir"
}
Normalize-WindowsPathEnvironment

if (Test-WindowsHost) {
	Ensure-GeneratedVisualStudioProject -ExampleName $Example -ExamplePath $exampleDir -OfRoot $ofRoot
	$project = Join-Path $exampleDir "$Example.vcxproj"
	if (!(Test-Path -LiteralPath $project)) {
		throw "Visual Studio project not found: $project. Generate it with the openFrameworks projectGenerator first."
	}
	$addonDefines = Get-AddonDefines
	$addonIncludeDirs = Get-AddonIncludeDirectories
	Repair-VisualStudioProjectFile -Path $project -AddonDefines $addonDefines -AddonIncludeDirs $addonIncludeDirs
	Repair-VisualStudioProjectFile -Path "$project.filters"
	if ($RepairOnly) {
		Write-Step "Repair-only project metadata check completed for $Example"
		return
	}
	$msbuild = Get-MsBuild
	if ([string]::IsNullOrWhiteSpace($msbuild)) {
		throw "MSBuild.exe was not found."
	}

	$target = if ($Clean) { "Rebuild" } else { "Build" }
	$buildJobs = Resolve-BuildJobs -RequestedJobs $Jobs
	$parallelArgs = Get-MsBuildParallelArguments -BuildJobs $buildJobs
	Write-Step "Building $Example $Configuration $Platform with MSBuild ($buildJobs jobs)"
	$lockName = "Local\ofxGgml-msbuild-" + (Get-StableNameFragment $ofRoot)
	Invoke-WithNamedMutex -Name $lockName -Command {
		$exitCode = 0
		for ($attempt = 1; $attempt -le 2; $attempt++) {
			& $msbuild $project /t:$target /p:Configuration=$Configuration /p:Platform=$Platform /p:TrackFileAccess=false @parallelArgs /nr:false
			$exitCode = $LASTEXITCODE
			if ($exitCode -eq 0) {
				return
			}
			if ($attempt -lt 2) {
				Write-Step "MSBuild failed with exit code $exitCode; retrying once"
			}
		}
		if (!$Clean) {
			Write-Step "MSBuild failed with exit code $exitCode; retrying without rebuilding project references"
			& $msbuild $project /t:$target /p:Configuration=$Configuration /p:Platform=$Platform /p:TrackFileAccess=false @parallelArgs /p:BuildProjectReferences=false /nr:false
			$exitCode = $LASTEXITCODE
			if ($exitCode -eq 0) {
				return
			}
		}
		throw "MSBuild $Example failed with exit code $exitCode"
	}
	return
}

$makefile = Join-Path $exampleDir "Makefile"
if (Test-Path -LiteralPath $makefile) {
	$target = if ($Clean) { "clean Release" } else { "Release" }
	Write-Step "Building $Example with make"
	Invoke-CheckedNative "make $Example" {
		make -C $exampleDir $target
	}
	return
}

if ($IsMacOS) {
	$xcodeProject = Get-ChildItem -LiteralPath $exampleDir -Filter "*.xcodeproj" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($xcodeProject) {
		Write-Step "Building $Example $Configuration with xcodebuild"
		Invoke-CheckedNative "xcodebuild $Example" {
			xcodebuild -project $xcodeProject.FullName -configuration $Configuration
		}
		return
	}
}

throw "No supported generated project was found for $Example. Generate the example project with openFrameworks projectGenerator first."
