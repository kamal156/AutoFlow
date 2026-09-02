<#
.SYNOPSIS
  Stage 1 of the AutoFlow pipeline: research a seed keyword and produce a job folder
  containing job.json (all publish metadata) and thumb.jpg.

.DESCRIPTION
  Runs a single agentic Claude Code call in headless mode with the Nexlev MCP server
  attached. One fat call does keyword research, longtail selection, thumbnail
  inspiration, thumbnail generation and metadata writing -- deliberately not six
  small calls, because each invocation reloads context and burns subscription usage.

.EXAMPLE
  .\new-job.ps1 -SeedKeyword "lofi study beats"

.EXAMPLE
  .\new-job.ps1 -SeedKeyword "rain sounds for sleep" -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SeedKeyword,

    # Override the auto-generated folder name.
    [string]$Slug,

    # Render the resolved prompt and exit without calling Claude.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$root       = Split-Path -Parent $PSScriptRoot
$promptPath = Join-Path $root 'prompts\research.md'
$validator  = Join-Path $root 'scripts\validate-job.js'
$nodeExe    = 'C:\Users\kamal\tools\node\node.exe'

# --- slug -------------------------------------------------------------------
if (-not $Slug) {
    $Slug = $SeedKeyword.ToLower()
    $Slug = [regex]::Replace($Slug, '[^a-z0-9]+', '-')
    $Slug = $Slug.Trim('-')
    if ($Slug.Length -gt 60) { $Slug = $Slug.Substring(0, 60).Trim('-') }
}
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$jobDir = Join-Path $root ("jobs\{0}-{1}" -f $stamp, $Slug)

# --- preflight --------------------------------------------------------------
if (-not (Test-Path $promptPath)) { throw "Prompt not found: $promptPath" }
if (-not (Test-Path $nodeExe))    { throw "Node not found: $nodeExe" }

# Resolve the CLI without depending on PATH: a freshly-added PATH entry is not
# visible to shells that were already open, which otherwise makes this fail in a
# way that looks like a broken install.
$claudeExe = $null
$onPath = Get-Command claude -ErrorAction SilentlyContinue
if ($onPath) {
    $claudeExe = $onPath.Source
} else {
    $shim = Join-Path $root 'npm-global\claude.cmd'
    if (Test-Path $shim) { $claudeExe = $shim }
}

if (-not $claudeExe -and -not $DryRun) {
    Write-Host ""
    Write-Host "The 'claude' CLI was not found." -ForegroundColor Red
    Write-Host "Install it, then connect Nexlev:" -ForegroundColor Yellow
    Write-Host "  npm config set prefix `"$root\npm-global`""
    Write-Host "  npm install -g --allow-scripts=@anthropic-ai/claude-code @anthropic-ai/claude-code"
    Write-Host "  claude mcp add --transport http nexlev https://prod.dashboard.nexlev.io/api/claude-mcp"
    Write-Host "  claude          # then run /mcp and authenticate nexlev once (OAuth, browser)"
    Write-Host ""
    throw "claude CLI unavailable"
}

New-Item -ItemType Directory -Path $jobDir -Force | Out-Null

# --- resolve the prompt -----------------------------------------------------
# .Replace() not -replace: the seed keyword is user text and must not be
# interpreted as a regex or as a $-substitution in the replacement.
$prompt = Get-Content $promptPath -Raw
$prompt = $prompt.Replace('{{SEED_KEYWORD}}', $SeedKeyword)
$prompt = $prompt.Replace('{{JOB_DIR}}', $jobDir.Replace([char]92, [char]47))
$prompt = $prompt.Replace('{{SLUG}}', $Slug)

$promptFile = Join-Path $jobDir '_prompt.md'
$prompt | Out-File -FilePath $promptFile -Encoding utf8

if ($DryRun) {
    Write-Host "Dry run. Resolved prompt written to:" -ForegroundColor Cyan
    Write-Host "  $promptFile"
    Write-Host "Job dir: $jobDir"
    exit 0
}

# --- run the agent ----------------------------------------------------------
Write-Host "Researching '$SeedKeyword'..." -ForegroundColor Cyan
Write-Host "  job dir: $jobDir"

$sessionLog = Join-Path $jobDir '_session.json'
$allowed = 'mcp__nexlev,Write,Bash(curl:*)'

Get-Content $promptFile -Raw | & $claudeExe -p --output-format json --allowedTools $allowed --add-dir $jobDir | Out-File -FilePath $sessionLog -Encoding utf8
$claudeExit = $LASTEXITCODE

if ($claudeExit -ne 0) {
    Write-Host "claude exited with code $claudeExit. Session log: $sessionLog" -ForegroundColor Red
    exit $claudeExit
}

# --- validate ---------------------------------------------------------------
$jobJson = Join-Path $jobDir 'job.json'
if (-not (Test-Path $jobJson)) {
    Write-Host "Agent did not write job.json. Session log: $sessionLog" -ForegroundColor Red
    exit 1
}

Write-Host ""
& $nodeExe $validator $jobJson
$valid = $LASTEXITCODE

if ($valid -ne 0) {
    Write-Host ""
    Write-Host "Validation failed. Inspect and fix, or re-run:" -ForegroundColor Red
    Write-Host "  $jobJson"
    exit $valid
}

Write-Host ""
Write-Host "Next: drop 6-8 Suno tracks into" -ForegroundColor Green
Write-Host "  $jobDir\audio\"
New-Item -ItemType Directory -Path (Join-Path $jobDir 'audio') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $jobDir 'render') -Force | Out-Null
exit 0
