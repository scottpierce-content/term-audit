# -----------------------------
# CONFIG
# -----------------------------
$RepoUrl        = "https://github.com/MicrosoftDocs/microsoft-style-guide.git"
$LocalPath      = "$env:TEMP\microsoft-style-guide"
$GlossaryPath   = "product-style-guide-msft-internal/a_z_names_terms"   # forward slashes for Git paths
$OutputCsv      = "$PWD\mpsg_glossary_export.csv"
$LearnBaseUrl   = "https://learn.microsoft.com/en-us/product-style-guide-msft-internal/a_z_names_terms"
$GitHubBaseUrl  = "https://github.com/MicrosoftDocs/microsoft-style-guide/blob/main"

# If you want Git to follow renames/moves for a file's history:
$FollowRenames  = $false

# -----------------------------
# PRECHECKS
# -----------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git is not installed or not on PATH. Install Git and retry."
}

# -----------------------------
# CLONE OR UPDATE REPO
# -----------------------------
if (-not (Test-Path $LocalPath)) {
    git clone $RepoUrl $LocalPath | Out-Null
} else {
    git -C $LocalPath pull | Out-Null
}

$FullGlossaryPath = Join-Path $LocalPath ($GlossaryPath -replace '/', '\')

# -----------------------------
# HELPER: get created + last modified (ISO 8601) from git history for one file
# -----------------------------
function Get-GitCreatedAndModifiedIso {
    param(
        [Parameter(Mandatory=$true)][string]$RepoRoot,
        [Parameter(Mandatory=$true)][string]$RepoRelativePath,
        [Parameter(Mandatory=$true)][bool]$Follow
    )

    # git log returns commits newest -> oldest by default. First line = modified, last line = created. 【2-ea6813】
    # %cI = strict ISO 8601 committer date. 【1-6a3254】

    $args = @("log")
    if ($Follow) { $args += "--follow" }  # --follow works for a single file. 【1-6a3254】
    $args += @("--format=%cI", "--", $RepoRelativePath)

    $out = git -C $RepoRoot @args 2>$null
    $lines = @($out) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if ($lines.Count -eq 0) {
        return @{
            created_iso  = $null
            modified_iso = $null
        }
    }

    return @{
        modified_iso = $lines[0].Trim()
        created_iso  = $lines[-1].Trim()
    }
}

# -----------------------------
# COLLECT TERMS
# -----------------------------
$rows = New-Object System.Collections.Generic.List[object]

Get-ChildItem $FullGlossaryPath -Directory | ForEach-Object {
    $letter = $_.Name

    Get-ChildItem $_.FullName -Filter *.md -File | ForEach-Object {
        $slug = $_.BaseName

        # Repo-relative path (Git wants forward slashes)
        $repoRel = "$GlossaryPath/$letter/$slug.md"

        $dates = Get-GitCreatedAndModifiedIso -RepoRoot $LocalPath -RepoRelativePath $repoRel -Follow $FollowRenames

        # Normalize to UTC strings (optional but useful for sorting)
        $created_utc  = $null
        $modified_utc = $null

        if ($dates.created_iso) {
            try {
                $created_utc = ([DateTimeOffset]::Parse($dates.created_iso)).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            } catch { $created_utc = $null }
        }

        if ($dates.modified_iso) {
            try {
                $modified_utc = ([DateTimeOffset]::Parse($dates.modified_iso)).UtcDateTime.ToString("yyyy-MM-ddTHH:mm:ssZ")
            } catch { $modified_utc = $null }
        }

        $rows.Add([PSCustomObject]@{
            letter              = $letter
            term_slug           = $slug
            learn_url           = "$LearnBaseUrl/$letter/$slug"
            github_url          = "$GitHubBaseUrl/$GlossaryPath/$letter/$slug.md"
            created_iso         = $dates.created_iso
            created_utc         = $created_utc
            last_modified_iso   = $dates.modified_iso
            last_modified_utc   = $modified_utc
        })
    }
}

# -----------------------------
# EXPORT CSV
# -----------------------------
$rows |
    Sort-Object letter, term_slug |
    Export-Csv $OutputCsv -NoTypeInformation -Encoding UTF8

Write-Host "✅ Export complete:"
Write-Host $OutputCsv
