param(
    [string]$OutputPath = "",
    [switch]$Json,
    [switch]$SummaryOnly
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonRoot = Resolve-Path (Join-Path $scriptRoot "..")

Push-Location $addonRoot
try {
    $checks = [System.Collections.Generic.List[hashtable]]::new()
    $score = 0
    $maxScore = 0

    function Test-PathLeaf { param([string]$p) return (Test-Path -LiteralPath $p -PathType Leaf) }
    function Test-PathDir  { param([string]$p) return (Test-Path -LiteralPath $p -PathType Container) }

    $testItems = @(
        @{ Category="release_docs"; Name="CHANGELOG.md"; Weight=2; Test={ Test-PathLeaf "CHANGELOG.md" } },
        @{ Category="release_docs"; Name="RELEASE_POLICY.md"; Weight=1; Test={ Test-PathLeaf "docs\RELEASE_POLICY.md" } },
        @{ Category="release_docs"; Name="RELEASE_CHECKLIST.md"; Weight=1; Test={ Test-PathLeaf "docs\RELEASE_CHECKLIST.md" } },
        @{ Category="release_docs"; Name="RELEASE_NOTES_TEMPLATE.md"; Weight=1; Test={ Test-PathLeaf "docs\RELEASE_NOTES_TEMPLATE.md" } },
        @{ Category="release_docs"; Name="MIGRATION.md"; Weight=1; Test={ Test-PathLeaf "docs\MIGRATION.md" } },
        @{ Category="addon_structure"; Name="addon_config.mk"; Weight=2; Test={ Test-PathLeaf "addon_config.mk" } },
        @{ Category="addon_structure"; Name="README.md"; Weight=2; Test={ Test-PathLeaf "README.md" } },
        @{ Category="addon_structure"; Name="LICENSE"; Weight=1; Test={ Test-PathLeaf "LICENSE" } },
        @{ Category="addon_structure"; Name="ofxggml-addon.json"; Weight=2; Test={ Test-PathLeaf "ofxggml-addon.json" } },
        @{ Category="scripts"; Name="validate-local.ps1"; Weight=2; Test={ Test-PathLeaf "scripts\validate-local.ps1" } },
        @{ Category="scripts"; Name="build-llama-server.ps1"; Weight=1; Test={ Test-PathLeaf "scripts\build-llama-server.ps1" } },
        @{ Category="scripts"; Name="run-llama-runtime-smoke.ps1"; Weight=2; Test={ Test-PathLeaf "scripts\run-llama-runtime-smoke.ps1" } },
        @{ Category="scripts"; Name="release-candidate.ps1"; Weight=1; Test={ Test-PathLeaf "scripts\release-candidate.ps1" } },
        @{ Category="workflows"; Name="addon-hygiene.yml"; Weight=1; Test={ Test-PathLeaf ".github\workflows\addon-hygiene.yml" } },
        @{ Category="workflows"; Name="coding-agent-instructions.yml"; Weight=1; Test={ Test-PathLeaf ".github\workflows\coding-agent-instructions.yml" } },
        @{ Category="workflows"; Name="metadata-validation.yml"; Weight=1; Test={ Test-PathLeaf ".github\workflows\metadata-validation.yml" } },
        @{ Category="workflows"; Name="release-check.yml"; Weight=1; Test={ Test-PathLeaf ".github\workflows\release-check.yml" } },
        @{ Category="workflows"; Name="backend-runtime-check.yml"; Weight=1; Test={ Test-PathLeaf ".github\workflows\backend-runtime-check.yml" } },
        @{ Category="tests"; Name="CMakeLists.txt"; Weight=2; Test={ Test-PathLeaf "tests\CMakeLists.txt" } },
        @{ Category="tests"; Name="test_main.cpp"; Weight=2; Test={ Test-PathLeaf "tests\test_main.cpp" } },
        @{ Category="examples"; Name="ofxGgmlTextExample"; Weight=1; Test={ Test-PathDir "ofxGgmlTextExample" } },
        @{ Category="examples"; Name="ofxGgmlChatExample"; Weight=1; Test={ Test-PathDir "ofxGgmlChatExample" } },
        @{ Category="examples"; Name="ofxGgmlEmbeddingExample"; Weight=1; Test={ Test-PathDir "ofxGgmlEmbeddingExample" } },
        @{ Category="examples"; Name="ofxGgmlLlamaCodexLocalExample"; Weight=1; Test={ Test-PathDir "ofxGgmlLlamaCodexLocalExample" } },
        @{ Category="hygiene"; Name="gitignore_build"; Weight=1; Test={ (Get-Content ".gitignore" -Raw) -match "build/" } },
        @{ Category="hygiene"; Name="gitignore_binaries"; Weight=1; Test={ $ig = (Get-Content ".gitignore" -Raw); $ig -match "\.exe" -and $ig -match "\.dll" } },
        @{ Category="hygiene"; Name="gitignore_models"; Weight=1; Test={ (Get-Content ".gitignore" -Raw) -match "models/" } }
    )

    foreach ($item in $testItems) {
        $maxScore += $item.Weight
        $passed = $false
        try { $passed = & $item.Test } catch { $false }
        if ($passed) { $score += $item.Weight }
        $checks.Add(@{ Category=$item.Category; Name=$item.Name; Passed=$passed; Weight=$item.Weight })
    }

    $percentage = [math]::Round(($score / $maxScore) * 100, 1)
    $grade = if ($percentage -ge 90) { "A" } elseif ($percentage -ge 75) { "B" } elseif ($percentage -ge 60) { "C" } else { "D" }

    $result = @{
        Addon = "ofxGgmlLlama"
        Score = $score
        MaxScore = $maxScore
        Percentage = $percentage
        Grade = $grade
        Checks = $checks.ToArray()
        Generated = (Get-Date).ToUniversalTime().ToString("o")
    }

    if ($Json) {
        $content = ($result | ConvertTo-Json -Depth 6)
        if (![string]::IsNullOrWhiteSpace($OutputPath)) {
            $target = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $addonRoot $OutputPath }
            $dir = Split-Path -Parent $target
            if (!(Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            Set-Content -LiteralPath $target -Value $content
        }
        $content
    } else {
        Write-Host "ofxGgmlLlama release readiness score"
        Write-Host "Score:      $score/$maxScore ($percentage%)"
        Write-Host "Grade:      $grade"
        foreach ($check in $checks) {
            $icon = if ($check.Passed) { "PASS" } else { "FAIL" }
            Write-Host "  [$icon] $($check.Category)/$($check.Name) (weight $($check.Weight))"
        }
        if (![string]::IsNullOrWhiteSpace($OutputPath)) {
            $mdLines = @("# Release Readiness Score", "", "**Addon:** ofxGgmlLlama", "**Score:** $score/$maxScore ($percentage%)", "**Grade:** $grade", "**Generated:** $($result.Generated)", "")
            foreach ($check in $checks) {
                $icon = if ($check.Passed) { ":white_check_mark:" } else { ":x:" }
                $mdLines += "$icon **$($check.Category)/$($check.Name)** (weight $($check.Weight))"
            }
            $mdLines += ""
            $mdPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { $OutputPath } else { Join-Path $addonRoot $OutputPath }
            $mdDir = Split-Path -Parent $mdPath
            if (!(Test-Path -LiteralPath $mdDir -PathType Container)) { New-Item -ItemType Directory -Path $mdDir -Force | Out-Null }
            Set-Content -LiteralPath $mdPath -Value ($mdLines -join "`n")
        }
    }
} finally {
    Pop-Location
}
