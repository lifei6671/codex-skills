#!/usr/bin/env pwsh
#
# Autonomous Skill - Session Runner (PowerShell)
# Executes Codex in non-interactive mode with auto-continuation
#
# Usage:
#   ./run-session.ps1 "task description"
#   ./run-session.ps1 --task-name <name> --continue
#   ./run-session.ps1 --list
#   ./run-session.ps1 --help
#

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Configuration
$AUTO_CONTINUE_DELAY = 3

# Use CODEX_PLUGIN_ROOT or fallback to script directory
if ($env:CODEX_PLUGIN_ROOT) {
    $SKILL_DIR = Join-Path $env:CODEX_PLUGIN_ROOT "skills/autonomous-skill"
} else {
    $SKILL_DIR = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

# Task directory base (in project root)
$AUTONOMOUS_DIR = ".autonomous"

$script:CurrentTaskName = ""

function Print-Header([string]$Text) {
    Write-Host "==========================================" -ForegroundColor Blue
    Write-Host "  $Text" -ForegroundColor Blue
    Write-Host "==========================================" -ForegroundColor Blue
}

function Print-Success([string]$Text) {
    Write-Host "✓ $Text" -ForegroundColor Green
}

function Print-Warning([string]$Text) {
    Write-Host "⚠ $Text" -ForegroundColor Yellow
}

function Print-Error([string]$Text) {
    Write-Host "✗ $Text" -ForegroundColor Red
}

function Print-Info([string]$Text) {
    Write-Host "ℹ $Text" -ForegroundColor Cyan
}

function Show-Help {
    Write-Host "Autonomous Skill - Session Runner (Codex)"
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  $($MyInvocation.MyCommand.Name) ""task description""           Start new task (auto-generates name)"
    Write-Host "  $($MyInvocation.MyCommand.Name) --task-name <name> --continue Continue specific task"
    Write-Host "  $($MyInvocation.MyCommand.Name) --list                        List all tasks"
    Write-Host "  $($MyInvocation.MyCommand.Name) --help                        Show this help"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  --task-name <name>       Specify task name explicitly"
    Write-Host "  --continue, -c           Continue existing task"
    Write-Host "  --no-auto-continue       Don't auto-continue after session"
    Write-Host "  --max-sessions N         Limit to N sessions"
    Write-Host "  --list                   List all existing tasks"
    Write-Host "  --resume-last            Resume the most recent Codex session"
    Write-Host "  --network                Enable network access (uses danger-full-access sandbox)"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  $($MyInvocation.MyCommand.Name) ""Build a REST API for todo app"""
    Write-Host "  $($MyInvocation.MyCommand.Name) --task-name build-rest-api --continue"
    Write-Host "  $($MyInvocation.MyCommand.Name) --task-name build-rest-api --continue --resume-last"
    Write-Host "  $($MyInvocation.MyCommand.Name) --list"
    Write-Host ""
    Write-Host "Task Directory: $AUTONOMOUS_DIR/<task-name>/"
    Write-Host "Skill Directory: $SKILL_DIR"
    Write-Host ""
}

function Generate-TaskName([string]$Desc) {
    $result = ($Desc.ToLowerInvariant() -replace '[^a-z0-9]', '-') -replace '-{2,}', '-'
    $result = $result.Trim('-')
    if ($result.Length -gt 30) {
        $result = $result.Substring(0, 30).Trim('-')
    }
    if ([string]::IsNullOrWhiteSpace($result)) {
        $result = "task-$(Get-Date -Format yyyyMMdd-HHmmss)"
        Print-Warning "Non-alphanumeric description detected, using generated name: $result"
    }
    return $result
}

function Validate-TaskName([string]$Name) {
    if ($Name -match '\.\.' -or $Name -match '/' -or $Name -match '\\') {
        Print-Error "Invalid task name: '$Name' (contains path traversal characters)"
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Print-Error "Task name cannot be empty"
        return $false
    }
    if ($Name.StartsWith("-")) {
        Print-Error "Task name cannot start with a hyphen"
        return $false
    }
    return $true
}

function Check-Dependencies {
    if (-not (Get-Command codex -ErrorAction SilentlyContinue)) {
        Print-Error "Required command 'codex' not found"
        Write-Host "Please install Codex CLI: https://github.com/openai/codex"
        exit 1
    }
}

function List-Tasks {
    Print-Header "AUTONOMOUS TASKS"

    if (-not (Test-Path $AUTONOMOUS_DIR)) {
        Print-Warning "No tasks found. Directory $AUTONOMOUS_DIR does not exist."
        Write-Host ""
        return
    }

    $taskDirs = Get-ChildItem -Path $AUTONOMOUS_DIR -Directory -ErrorAction SilentlyContinue
    if (-not $taskDirs -or $taskDirs.Count -eq 0) {
        Print-Warning "No tasks found in $AUTONOMOUS_DIR/"
        Write-Host ""
        return
    }

    $found = 0
    foreach ($taskDir in $taskDirs) {
        $taskName = $taskDir.Name
        $taskList = Join-Path $taskDir.FullName "task_list.md"
        if (Test-Path $taskList) {
            $total = (Select-String -Path $taskList -Pattern '^\- \[' -AllMatches -ErrorAction SilentlyContinue).Count
            $doneCount = (Select-String -Path $taskList -Pattern '^\- \[x\]' -AllMatches -ErrorAction SilentlyContinue).Count
            $percent = 0
            if ($total -gt 0) {
                $percent = [int](($doneCount * 100) / $total)
            }

            $sessionInfo = ""
            $sessionIdPath = Join-Path $taskDir.FullName "session.id"
            if (Test-Path $sessionIdPath) {
                $sid = (Get-Content $sessionIdPath -ErrorAction SilentlyContinue | Select-Object -First 1)
                if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }
                if (-not [string]::IsNullOrWhiteSpace($sid)) {
                    $sessionInfo = " [session: ${sid}...]"
                }
            }

            if ($doneCount -eq $total -and $total -gt 0) {
                Write-Host "  ✓ $taskName ($doneCount/$total - 100% complete)$sessionInfo" -ForegroundColor Green
            } else {
                Write-Host "  ○ $taskName ($doneCount/$total - $percent%)$sessionInfo" -ForegroundColor Yellow
            }
            $found++
        } else {
            Write-Host "  ? $taskName (no task_list.md)" -ForegroundColor Red
            $found++
        }
    }

    if ($found -eq 0) {
        Print-Warning "No valid tasks found in $AUTONOMOUS_DIR/"
    }

    Write-Host ""
}

function Task-Exists([string]$TaskName) {
    return Test-Path (Join-Path $AUTONOMOUS_DIR "$TaskName/task_list.md")
}

function Get-TaskDir([string]$TaskName) {
    return (Join-Path $AUTONOMOUS_DIR $TaskName)
}

function Get-Progress([string]$TaskDir) {
    $taskList = Join-Path $TaskDir "task_list.md"
    if (Test-Path $taskList) {
        $total = (Select-String -Path $taskList -Pattern '^\- \[' -AllMatches -ErrorAction SilentlyContinue).Count
        $done = (Select-String -Path $taskList -Pattern '^\- \[x\]' -AllMatches -ErrorAction SilentlyContinue).Count
        return "$done/$total"
    }
    return "0/0"
}

function Is-Complete([string]$TaskDir) {
    $taskList = Join-Path $TaskDir "task_list.md"
    if (Test-Path $taskList) {
        $total = (Select-String -Path $taskList -Pattern '^\- \[' -AllMatches -ErrorAction SilentlyContinue).Count
        $done = (Select-String -Path $taskList -Pattern '^\- \[x\]' -AllMatches -ErrorAction SilentlyContinue).Count
        if ($done -eq $total -and $total -gt 0) {
            return $true
        }
    }
    return $false
}

function Extract-SessionId([string]$LogFile) {
    if (-not (Test-Path $LogFile)) { return "" }
    $line = Select-String -Path $LogFile -Pattern '"type":"thread.started"' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $line) { return "" }
    $match = [regex]::Match($line.Line, '"thread_id":"([^"]+)"')
    if ($match.Success) { return $match.Groups[1].Value }
    return ""
}

function Run-Initializer([string]$TaskName, [string]$TaskDesc, [bool]$EnableNetwork) {
    $taskDir = Get-TaskDir $TaskName

    Print-Header "INITIALIZER SESSION"
    Write-Host "Task: $TaskDesc"
    Write-Host "Task Name: $TaskName"
    Write-Host "Task Directory: $taskDir"
    Write-Host ""

    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null

    $initPrompt = (Get-Content -Path (Join-Path $SKILL_DIR "templates/initializer-prompt.md") -Raw) -replace '\{TASK_DIR\}', $taskDir

    $codexArgs = @("exec", "--skip-git-repo-check", "--full-auto", "--json")
    if ($EnableNetwork) {
        $codexArgs = @("exec", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", "--json")
    }

    $prompt = @"
Task: $TaskDesc
Task Name: $TaskName
Task Directory: $taskDir

You are the Initializer Agent. Create task_list.md and progress.md in the $taskDir directory. All task files must be created in $taskDir/, not in the current directory.

$initPrompt
"@

    & codex @codexArgs $prompt 2>&1 | Tee-Object -FilePath (Join-Path $taskDir "session.log")

    $sessionId = Extract-SessionId (Join-Path $taskDir "session.log")
    if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
        $sessionId | Set-Content -Path (Join-Path $taskDir "session.id")
        Print-Info "Session ID saved: $sessionId"
    }

    Write-Host ""
    Print-Success "Initializer session complete"
}

function Run-Executor([string]$TaskName, [bool]$ResumeLast, [bool]$EnableNetwork) {
    $taskDir = Get-TaskDir $TaskName

    Print-Header "EXECUTOR SESSION"
    Write-Host "Task Name: $TaskName"
    Write-Host "Task Directory: $taskDir"
    Write-Host ""

    $taskList = Get-Content -Path (Join-Path $taskDir "task_list.md") -Raw -ErrorAction SilentlyContinue
    if (-not $taskList) { $taskList = "No task list found" }
    $progressNotes = Get-Content -Path (Join-Path $taskDir "progress.md") -Raw -ErrorAction SilentlyContinue
    if (-not $progressNotes) { $progressNotes = "No progress notes yet" }

    $execPrompt = (Get-Content -Path (Join-Path $SKILL_DIR "templates/executor-prompt.md") -Raw) -replace '\{TASK_DIR\}', $taskDir

    $codexArgs = @("exec", "--skip-git-repo-check", "--full-auto", "--json")
    if ($EnableNetwork) {
        $codexArgs = @("exec", "--skip-git-repo-check", "--dangerously-bypass-approvals-and-sandbox", "--json")
    }

    $prompt = @"
Continue working on the task.
Task Name: $TaskName
Task Directory: $taskDir

You are the Executor Agent. Complete tasks and update files in the $taskDir directory. All task files are in $taskDir/, not in the current directory.

Current task_list.md:
$taskList

Previous progress notes:
$progressNotes

$execPrompt
"@

    if ($ResumeLast -and (Test-Path (Join-Path $taskDir "session.id"))) {
        $sessionId = (Get-Content (Join-Path $taskDir "session.id") -ErrorAction SilentlyContinue | Select-Object -First 1)
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            Print-Info "Resuming session: $sessionId"
            & codex @codexArgs "resume" $sessionId $prompt 2>&1 | Tee-Object -FilePath (Join-Path $taskDir "session.log") -Append
        } else {
            & codex @codexArgs $prompt 2>&1 | Tee-Object -FilePath (Join-Path $taskDir "session.log")
        }
    } else {
        & codex @codexArgs $prompt 2>&1 | Tee-Object -FilePath (Join-Path $taskDir "session.log")
        $sessionId = Extract-SessionId (Join-Path $taskDir "session.log")
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            $sessionId | Set-Content -Path (Join-Path $taskDir "session.id")
            Print-Info "Session ID saved: $sessionId"
        }
    }

    Write-Host ""
    Print-Success "Executor session complete"
}

function Main([string[]]$Args) {
    $taskDesc = ""
    $taskName = ""
    $autoContinue = $true
    $maxSessions = 0
    $sessionNum = 1
    $continueMode = $false
    $resumeLast = $false
    $enableNetwork = $false

    for ($i = 0; $i -lt $Args.Length; $i++) {
        switch ($Args[$i]) {
            "--help" { Show-Help; exit 0 }
            "-h" { Show-Help; exit 0 }
            "--list" { List-Tasks; exit 0 }
            "-l" { List-Tasks; exit 0 }
            "--task-name" {
                if ($i + 1 -lt $Args.Length) { $taskName = $Args[$i + 1]; $i++ }
            }
            "-n" {
                if ($i + 1 -lt $Args.Length) { $taskName = $Args[$i + 1]; $i++ }
            }
            "--continue" { $continueMode = $true }
            "-c" { $continueMode = $true }
            "--no-auto-continue" { $autoContinue = $false }
            "--max-sessions" {
                if ($i + 1 -lt $Args.Length) { $maxSessions = [int]$Args[$i + 1]; $i++ }
            }
            "--resume-last" { $resumeLast = $true }
            "--network" { $enableNetwork = $true }
            Default { $taskDesc = $Args[$i] }
        }
    }

    if ([string]::IsNullOrWhiteSpace($taskName) -and -not [string]::IsNullOrWhiteSpace($taskDesc)) {
        $taskName = Generate-TaskName $taskDesc
        Print-Info "Generated task name: $taskName"
    }

    if ([string]::IsNullOrWhiteSpace($taskName)) {
        if ($continueMode) {
            if (Test-Path $AUTONOMOUS_DIR) {
                $last = Get-ChildItem -Path $AUTONOMOUS_DIR -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($last) { $taskName = $last.Name }
            }
            if ([string]::IsNullOrWhiteSpace($taskName)) {
                Print-Error "No task name provided and no existing tasks found"
                Write-Host "Usage: $($MyInvocation.MyCommand.Name) ""Your task description"""
                Write-Host "       $($MyInvocation.MyCommand.Name) --task-name <name> --continue"
                exit 1
            }
            Print-Info "Continuing most recent task: $taskName"
        } else {
            Print-Error "No task description or name provided"
            Show-Help
            exit 1
        }
    }

    if (-not (Validate-TaskName $taskName)) { exit 1 }

    Check-Dependencies

    $taskDir = Get-TaskDir $taskName
    $script:CurrentTaskName = $taskName

    while ($true) {
        Write-Host ""
        Print-Header "SESSION $sessionNum - $taskName"

        if (Task-Exists $taskName) {
            Write-Host "Progress: $(Get-Progress $taskDir)"
            Write-Host ""
        }

        if (Task-Exists $taskName) {
            Run-Executor $taskName $resumeLast $enableNetwork
            $resumeLast = $false
        } else {
            if ([string]::IsNullOrWhiteSpace($taskDesc)) {
                Print-Error "Task '$taskName' not found and no description provided"
                Write-Host "Provide a task description to initialize: $($MyInvocation.MyCommand.Name) ""Your task description"""
                exit 1
            }
            Run-Initializer $taskName $taskDesc $enableNetwork
        }

        Write-Host ""
        Write-Host "=== Progress: $(Get-Progress $taskDir) ==="

        if (Is-Complete $taskDir) {
            Write-Host ""
            Print-Success "ALL TASKS COMPLETED!"
            Write-Host ""
            Write-Host "Task directory: $taskDir"
            Write-Host "Final task list:"
            Get-Content -Path (Join-Path $taskDir "task_list.md")
            exit 0
        }

        if ($maxSessions -gt 0 -and $sessionNum -ge $maxSessions) {
            Print-Warning "Reached maximum sessions ($maxSessions)"
            exit 0
        }

        if ($autoContinue) {
            Write-Host ""
            Write-Host "Continuing in $AUTO_CONTINUE_DELAY seconds... (Press Ctrl+C to pause)"
            for ($i = $AUTO_CONTINUE_DELAY; $i -ge 1; $i--) {
                Write-Host -NoNewline "`r$i... "
                Start-Sleep -Seconds 1
            }
            Write-Host ""
        } else {
            Write-Host ""
            Print-Warning "Auto-continue disabled. Run again to continue."
            exit 0
        }

        $sessionNum++
    }
}

Register-EngineEvent -InputObject ([Console]::CancelKeyPress) -EventName "CancelKeyPress" -Action {
    $Event.SourceEventArgs.Cancel = $true
    Write-Host ""
    Print-Warning "Interrupted. Progress saved in $AUTONOMOUS_DIR/$script:CurrentTaskName/"
    Write-Host "Run again to continue: $($MyInvocation.MyCommand.Name) --task-name $script:CurrentTaskName --continue"
    exit 130
} | Out-Null

Main $args
