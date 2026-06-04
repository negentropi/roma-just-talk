param(
    [string]$PackageDir = "",
    [string]$InstallDir = "",
    [string]$ConfigPath = "",
    [string]$ProofReportPath = "",
    [string]$ProofSessionId = "",
    [string]$Endpoint = "",
    [string]$Model = "",
    [string]$ApiKeyEnv = "",
    [string]$ApiKeyName = "",
    [string]$SecretDir = "",
    [string]$WhisperCLI = "",
    [string]$WhisperModel = "",
    [string]$WhisperOutputDir = "",
    [string[]]$WhisperArgument = @(),
    [string]$Language = "",
    [string]$Prompt = "",
    [string[]]$WordReplacement = @("just talk=roma-just-talk"),
    [string]$ExpectedTranscriptText = "",
    [switch]$UseHoldHook,
    [switch]$UseToggle,
    [int]$HoldTimeoutSeconds = 15,
    [int]$RecordSeconds = 2,
    [switch]$PasteDictation,
    [switch]$RestoreClipboard,
    [switch]$NoRestoreClipboard,
    [double]$ClipboardRestoreDelaySeconds = 2,
    [switch]$UsePackagedWhisperMock,
    [switch]$RunDictation,
    [switch]$CreateShortcut,
    [switch]$CreateStartupShortcut,
    [string]$ShortcutDir = "",
    [string]$StartupShortcutDir = "",
    [switch]$RunNotepadPasteProof,
    [string]$NotepadPasteProofPath = "",
    [string]$PasteProofText = "roma just talk proof",
    [switch]$DoctorOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$proofCommonScript = Join-Path $PSScriptRoot "windows-proof-common.ps1"
if (!(Test-Path -LiteralPath $proofCommonScript)) {
    throw "Windows proof common helper was not found: $proofCommonScript"
}
. $proofCommonScript
Set-Alias -Name Invoke-Step -Value Invoke-RomaWindowsProofStep -Scope Local -Force
Set-Alias -Name Resolve-FullPath -Value Resolve-RomaWindowsFullPath -Scope Local -Force
Set-Alias -Name Require-File -Value Require-RomaWindowsFile -Scope Local -Force
Set-Alias -Name Assert-OutputContains -Value Assert-RomaWindowsOutputContains -Scope Local -Force
Set-Alias -Name Get-FileProof -Value Get-RomaWindowsFileProof -Scope Local -Force
Set-Alias -Name Get-FileHashProof -Value Get-RomaWindowsFileHashProof -Scope Local -Force

$packageIdentityScript = Join-Path $PSScriptRoot "windows-package-identity.ps1"
if (!(Test-Path -LiteralPath $packageIdentityScript)) {
    throw "Windows package identity helper was not found: $packageIdentityScript"
}
. $packageIdentityScript

$manifestScript = Join-Path $PSScriptRoot "windows-manifest.ps1"
if (!(Test-Path -LiteralPath $manifestScript)) {
    throw "Windows manifest helper was not found: $manifestScript"
}
. $manifestScript

function Invoke-ProofAgentDoctorCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host ""
    Write-Host "-- $Name --"
    $output = & $script:proofAgentPath $Command 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaProofAgent $Command failed"
    }

    Write-Host $output
    return $output
}

function Invoke-PackagedListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $agentPath listen `
        --config $ConfigPath `
        --max-sessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaWindowsAgent listen smoke failed"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "mode=listen"
    Assert-OutputContains -Output $output -Expected "listener_capture_lifecycle=shared_pre_roll_runtime"
    Assert-OutputContains -Output $output -Expected "listen_completed_sessions=0"
    return $output
}

function Invoke-InstalledListenerSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    $output = & $RunScriptPath `
        -InstallDir $InstallDir `
        -ConfigPath $ConfigPath `
        -Listen `
        -MaxSessions 0 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "Installed launcher listen smoke failed"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "mode=RomaWindowsAgent listen"
    Assert-OutputContains -Output $output -Expected "listener_capture_lifecycle=shared_pre_roll_runtime"
    Assert-OutputContains -Output $output -Expected "listen_completed_sessions=0"
    return $output
}

function Invoke-ConfigDoctor {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AgentPath,
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    Require-File -Path $AgentPath
    Require-File -Path $ConfigPath
    $output = & $AgentPath config-doctor --config $ConfigPath 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        throw "RomaWindowsAgent config-doctor failed"
    }

    Write-Host $output
    Assert-OutputContains -Output $output -Expected "config_valid=true"
    Assert-OutputContains -Output $output -Expected "transcription_client="
    return $output
}

function Test-ContainsText {
    param(
        [string]$Text = "",
        [string]$Needle = ""
    )

    if ([string]::IsNullOrEmpty($Needle)) {
        return $false
    }

    return $Text.IndexOf($Needle, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
}

function Get-ShortcutProof {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$RunScriptPath,
        [string]$ConfigPath = "",
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $proof = Get-FileProof -Path $Path
    if (!$proof["exists"] -or
        [System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return $proof
    }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($Path)
    $targetPath = [string]$shortcut.TargetPath
    $arguments = [string]$shortcut.Arguments
    $savedWorkingDirectory = [string]$shortcut.WorkingDirectory
    $expectedFileArgument = "-File `"$RunScriptPath`""
    $expectedConfigArgument = "-ConfigPath `"$ConfigPath`""

    $proof["target_path"] = $targetPath
    $proof["arguments"] = $arguments
    $proof["working_directory"] = $savedWorkingDirectory
    $proof["description"] = [string]$shortcut.Description
    $proof["window_style"] = [int]$shortcut.WindowStyle
    $proof["target_is_powershell"] = $targetPath.EndsWith("powershell.exe", [System.StringComparison]::OrdinalIgnoreCase)
    $proof["references_run_script"] = ![string]::IsNullOrWhiteSpace($RunScriptPath) -and (Test-ContainsText -Text $arguments -Needle $RunScriptPath)
    $proof["references_config_path"] = ![string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-ContainsText -Text $arguments -Needle $ConfigPath)
    $proof["expected_file_argument"] = $expectedFileArgument
    $proof["expected_config_argument"] = $expectedConfigArgument
    $proof["has_exact_file_argument"] = Test-ContainsText -Text $arguments -Needle $expectedFileArgument
    $proof["has_config_path_argument"] = Test-ContainsText -Text $arguments -Needle "-ConfigPath"
    $proof["has_exact_config_argument"] = Test-ContainsText -Text $arguments -Needle $expectedConfigArgument
    $proof["has_no_profile_argument"] = Test-ContainsText -Text $arguments -Needle "-NoProfile"
    $proof["has_execution_policy_bypass"] = Test-ContainsText -Text $arguments -Needle "-ExecutionPolicy Bypass"
    $proof["runs_listener"] = Test-ContainsText -Text $arguments -Needle "-Listen"
    $proof["working_directory_is_install_dir"] = $savedWorkingDirectory.Equals($WorkingDirectory, [System.StringComparison]::OrdinalIgnoreCase)

    return $proof
}

function Wait-ProcessMainWindow {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before creating a main window: pid=$($Process.Id)"
        }
        if ($Process.MainWindowHandle -ne [IntPtr]::Zero) {
            Write-Host "process_window=ready pid=$($Process.Id) handle=$($Process.MainWindowHandle)"
            return
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out waiting for process main window: pid=$($Process.Id)"
}

function Set-ProcessForeground {
    param(
        [Parameter(Mandatory = $true)]
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds = 5
    )

    $shell = New-Object -ComObject WScript.Shell
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $Process.Refresh()
        if ($Process.HasExited) {
            throw "Process exited before activation: pid=$($Process.Id)"
        }
        if ($shell.AppActivate($Process.Id)) {
            Write-Host "process_foreground=activated pid=$($Process.Id)"
            return $shell
        }
        Start-Sleep -Milliseconds 200
    }

    throw "Timed out activating process: pid=$($Process.Id)"
}

function New-NotepadPasteProof {
    return [ordered]@{
        requested = $RunNotepadPasteProof.IsPresent
        text = $PasteProofText
        output_present = $false
        target_process_id = 0
        paste_sent = $false
        text_found = $false
        verified = $false
        file = Get-FileProof -Path $NotepadPasteProofPath
    }
}

function Invoke-NotepadPasteProof {
    $proof = New-NotepadPasteProof
    if (!$RunNotepadPasteProof) {
        return $proof
    }

    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        throw "RunNotepadPasteProof requires Windows"
    }
    if ([string]::IsNullOrWhiteSpace($PasteProofText)) {
        throw "PasteProofText must not be empty"
    }

    $notepadParent = Split-Path -Parent $NotepadPasteProofPath
    if (![string]::IsNullOrWhiteSpace($notepadParent)) {
        New-Item -ItemType Directory -Force -Path $notepadParent | Out-Null
    }
    Set-Content -LiteralPath $NotepadPasteProofPath -Encoding UTF8 -NoNewline -Value ""

    $notepad = Start-Process `
        -FilePath "notepad.exe" `
        -ArgumentList @("`"$NotepadPasteProofPath`"") `
        -PassThru

    try {
        Wait-ProcessMainWindow -Process $notepad
        $proof["target_process_id"] = $notepad.Id
        $pasteOutput = & $script:proofAgentPath windows-paste-proof `
            --text $PasteProofText `
            --target-process-id $notepad.Id 2>&1 | Out-String
        $proof["output_present"] = ![string]::IsNullOrWhiteSpace($pasteOutput)
        Write-Host $pasteOutput
        if ($LASTEXITCODE -ne 0) {
            throw "RomaProofAgent windows-paste-proof failed for Notepad"
        }
        Assert-OutputContains -Output $pasteOutput -Expected "target_process_id=$($notepad.Id)"
        Assert-OutputContains -Output $pasteOutput -Expected "paste_sent=true"
        $proof["paste_sent"] = $true

        $shell = Set-ProcessForeground -Process $notepad
        $shell.SendKeys("^s")
        Start-Sleep -Milliseconds 750

        $savedText = Get-Content -LiteralPath $NotepadPasteProofPath -Raw
        $proof["text_found"] = $savedText.Contains($PasteProofText)
        if (!$proof["text_found"]) {
            throw "Notepad file did not contain pasted proof text: $NotepadPasteProofPath"
        }

        $proof["verified"] = $true
        $proof["file"] = Get-FileProof -Path $NotepadPasteProofPath
        Write-Host "notepad_paste_file=$NotepadPasteProofPath"
        Write-Host "notepad_paste_verified=true"
        return $proof
    } finally {
        if ($null -ne $notepad) {
            $notepad.Refresh()
            if (!$notepad.HasExited) {
                $null = $notepad.CloseMainWindow()
                Start-Sleep -Milliseconds 500
                $notepad.Refresh()
            }
            if (!$notepad.HasExited) {
                Stop-Process -Id $notepad.Id -Force
            }
        }
    }
}

function Get-ConfigProof {
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        return [ordered]@{
            path = ""
            exists = $false
        }
    }

    $proof = Get-FileProof -Path $ConfigPath
    if (!$proof["exists"]) {
        return $proof
    }

    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ($config.PSObject.Properties.Name -contains "outputPath") {
        $outputPath = [string]$config.outputPath
        $proof["output_path"] = $outputPath
        if (![string]::IsNullOrWhiteSpace($outputPath)) {
            $proof["output_file"] = Get-FileProof -Path $outputPath
        }
    }
    if ($config.PSObject.Properties.Name -contains "usesHoldHook") {
        $proof["uses_hold_hook"] = [bool]$config.usesHoldHook
    }
    if ($config.PSObject.Properties.Name -contains "shouldPaste") {
        $proof["should_paste"] = [bool]$config.shouldPaste
    }
    if ($config.PSObject.Properties.Name -contains "restoreClipboardAfterPaste") {
        $proof["restore_clipboard_after_paste"] = [bool]$config.restoreClipboardAfterPaste
    }
    if ($config.PSObject.Properties.Name -contains "whisperCLIPath" -and
        ![string]::IsNullOrWhiteSpace([string]$config.whisperCLIPath)) {
        $proof["uses_whisper_cli"] = $true
        $proof["whisper_cli_path"] = [string]$config.whisperCLIPath
        $proof["whisper_cli_file"] = Get-FileProof -Path ([string]$config.whisperCLIPath)
        if ($config.PSObject.Properties.Name -contains "whisperModelPath") {
            $proof["whisper_model_path"] = [string]$config.whisperModelPath
            $proof["whisper_model_file"] = Get-FileProof -Path ([string]$config.whisperModelPath)
        }
    } else {
        $proof["uses_whisper_cli"] = $false
    }
    if ($config.PSObject.Properties.Name -contains "endpoint") {
        $proof["endpoint"] = [string]$config.endpoint
    }
    if ($config.PSObject.Properties.Name -contains "model") {
        $proof["model"] = [string]$config.model
    }

    return $proof
}

function Get-DictationRuntimeProof {
    $logPath = Join-Path (Join-Path $InstallDir "smoke") "windows-agent-dictate.log"
    $proof = Get-FileProof -Path $logPath
    if (!$proof["exists"]) {
        return $proof
    }

    $content = Get-Content -LiteralPath $logPath -Raw
    $wrotePath = Get-OutputValue -Content $content -Name "wrote"
    $durationSeconds = Get-OutputNumber -Content $content -Name "duration_seconds"
    $includedPreRollSeconds = Get-OutputNumber -Content $content -Name "included_pre_roll_seconds"
    $sampleRate = Get-OutputNumber -Content $content -Name "sample_rate"
    $channelCount = Get-OutputNumber -Content $content -Name "channels"
    $rawTranscriptLength = Get-OutputNumber -Content $content -Name "raw_transcript_length"
    $processedTranscriptLength = Get-OutputNumber -Content $content -Name "processed_transcript_length"
    $processedTranscriptText = Get-OutputValue -Content $content -Name "processed_transcript_text"
    $preRollBufferingLine = Get-OutputLineNumber -Content $content -Needle "pre_roll_buffering=true"
    $waitingForHoldLine = Get-OutputLineNumber -Content $content -Needle "waiting_for_key_down="
    $holdKeyDownLine = Get-OutputLineNumber -Content $content -Needle "hold_key_down=true"
    $holdKeyUpLine = Get-OutputLineNumber -Content $content -Needle "hold_key_up=true"
    $wroteLine = Get-OutputLineNumber -Content $content -Needle "wrote="
    $processedTextLine = Get-OutputLineNumber -Content $content -Needle "processed_transcript_text="
    $proof["reported_wrote"] = $content.Contains("wrote=")
    $proof["wrote_path"] = $wrotePath
    if (![string]::IsNullOrWhiteSpace($wrotePath)) {
        $proof["wrote_file"] = Get-FileProof -Path $wrotePath
    }
    $proof["reported_pre_roll"] = $content.Contains("included_pre_roll_seconds=")
    $proof["duration_seconds"] = $durationSeconds
    $proof["included_pre_roll_seconds"] = $includedPreRollSeconds
    $proof["reported_positive_duration"] = ($null -ne $durationSeconds) -and ($durationSeconds -gt 0)
    $proof["reported_positive_pre_roll"] = ($null -ne $includedPreRollSeconds) -and ($includedPreRollSeconds -gt 0)
    $proof["sample_rate"] = $sampleRate
    $proof["channels"] = $channelCount
    $proof["reported_speech_pcm_contract"] = (
        ($null -ne $sampleRate) -and
        ($null -ne $channelCount) -and
        ($sampleRate -eq 16000) -and
        ($channelCount -eq 1)
    )
    $proof["raw_transcript_length"] = $rawTranscriptLength
    $proof["processed_transcript_length"] = $processedTranscriptLength
    $proof["reported_positive_raw_transcript"] = ($null -ne $rawTranscriptLength) -and ($rawTranscriptLength -gt 0)
    $proof["reported_positive_processed_transcript"] = ($null -ne $processedTranscriptLength) -and ($processedTranscriptLength -gt 0)
    $proof["reported_processed_text"] = ![string]::IsNullOrWhiteSpace($processedTranscriptText)
    $proof["processed_transcript_text_present"] = ![string]::IsNullOrWhiteSpace($processedTranscriptText)
    $proof["reported_paste_sent"] = $content.Contains("paste_sent=true")
    $proof["reported_paste_not_sent"] = $content.Contains("paste_sent=false")
    $proof["reported_hold_mode"] = $content.Contains("recording_mode=hold")
    $proof["reported_waiting_for_hold_key_down"] = $content.Contains("waiting_for_key_down=")
    $proof["reported_hold_key_down"] = $content.Contains("hold_key_down=true")
    $proof["reported_hold_key_up"] = $content.Contains("hold_key_up=true")
    $proof["pre_roll_buffering_line"] = $preRollBufferingLine
    $proof["waiting_for_hold_key_down_line"] = $waitingForHoldLine
    $proof["hold_key_down_line"] = $holdKeyDownLine
    $proof["hold_key_up_line"] = $holdKeyUpLine
    $proof["wrote_line"] = $wroteLine
    $proof["processed_transcript_text_line"] = $processedTextLine
    $proof["reported_ordered_hold_sequence"] = (
        $preRollBufferingLine -gt 0 -and
        $waitingForHoldLine -gt $preRollBufferingLine -and
        $holdKeyDownLine -gt $waitingForHoldLine -and
        $holdKeyUpLine -gt $holdKeyDownLine -and
        $wroteLine -gt $holdKeyUpLine -and
        $processedTextLine -gt $wroteLine
    )
    $expectedTranscriptTextFound = $false
    if (![string]::IsNullOrWhiteSpace($ExpectedTranscriptText)) {
        $expectedTranscriptTextFound = Test-ContainsText -Text $processedTranscriptText -Needle $ExpectedTranscriptText
    }
    $proof["expected_transcript_text"] = $ExpectedTranscriptText
    $proof["expected_transcript_text_required"] = ![string]::IsNullOrWhiteSpace($ExpectedTranscriptText)
    $proof["expected_transcript_text_source"] = "processed_transcript_text"
    $proof["expected_transcript_text_found"] = $expectedTranscriptTextFound

    return $proof
}

function Get-OutputValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Content, "(?m)^$escapedName=(.+?)\s*$")
    if (!$match.Success) {
        return ""
    }

    return $match.Groups[1].Value
}

function Get-OutputNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $escapedName = [regex]::Escape($Name)
    $match = [regex]::Match($Content, "(?m)^$escapedName=([+-]?\d+(?:\.\d+)?)\s*$")
    if (!$match.Success) {
        return $null
    }

    return [double]::Parse(
        $match.Groups[1].Value,
        [System.Globalization.CultureInfo]::InvariantCulture
    )
}

function Get-OutputLineNumber {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Needle
    )

    $lines = $Content -split "\r?\n"
    for ($index = 0; $index -lt $lines.Count; $index += 1) {
        if ($lines[$index].Contains($Needle)) {
            return $index + 1
        }
    }

    return 0
}

function Get-DoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        runtime_available = $Output.Contains("runtime_available=true")
        dictation_runtime = $Output.Contains("dictation_runtime=WindowsDictationRuntime")
        recorder_miniaudio = $Output.Contains("recorder=miniaudio")
        paste_win32_clipboard_sendinput = $Output.Contains("paste=win32_clipboard_sendinput")
        secret_store_dpapi = $Output.Contains("secret_store=dpapi")
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsMinimumPermissionOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsRuntimeDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-ProofAgentDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        swift_core = $Output.Contains("swift_core=true")
        native_windows_adapters = $Output.Contains("native_windows_adapters=true")
        pre_roll_config = $Output.Contains("pre_roll_seconds=")
        windows_paste_adapter_source = $Output.Contains("windows_paste_adapter_source=true")
        windows_permission_surface_source = $Output.Contains("windows_permission_surface_source=true")
        windows_dictation_runtime_source = $Output.Contains("windows_dictation_runtime_source=true")
        windows_dictation_runtime_uses_pipeline_source = $Output.Contains("windows_dictation_runtime_uses_pipeline_source=true")
        windows_listener_output_isolation_source = $Output.Contains("windows_listener_output_isolation_source=true")
        windows_listener_pre_roll_runtime_source = $Output.Contains("windows_listener_pre_roll_runtime_source=true")
        windows_hold_hook_single_window_source = $Output.Contains("windows_hold_hook_single_window_source=true")
        windows_dictation_proof_source = $Output.Contains("windows_dictation_proof_source=true")
        miniaudio_capture_adapter_source = $Output.Contains("miniaudio_capture_adapter_source=true")
        openai_compatible_transcription_source = $Output.Contains("openai_compatible_transcription_source=true")
        whisper_cli_transcription_source = $Output.Contains("whisper_cli_transcription_source=true")
        roma_transcription_client_source = $Output.Contains("roma_transcription_client_source=true")
        transcription_output_filter_source = $Output.Contains("transcription_output_filter_source=true")
        word_replacement_processor_source = $Output.Contains("word_replacement_processor_source=true")
        windows_proof_args_shared_source = $Output.Contains("windows_proof_args_shared_source=true")
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsRuntimeDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-NativeDoctorOutputProof {
    param(
        [string]$Output = "",
        [Parameter(Mandatory = $true)]
        [string]$ExpectedMarker
    )

    $proof = [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        platform_windows = $Output.Contains("platform=windows")
        expected_marker = $ExpectedMarker
        expected_marker_present = $Output.Contains($ExpectedMarker)
        register_hotkey_available = $Output.Contains("hotkey_registration_available=true")
    }
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsHoldTimeoutDefaultOutputProof -Output $Output) | Out-Null
    Add-RomaWindowsProofFields -Proof $proof -Fields (Get-RomaWindowsClipboardRestoreDefaultOutputProof -Output $Output) | Out-Null
    return $proof
}

function Get-ListenerSmokeProof {
    param(
        [string]$Output = ""
    )

    $configPath = Get-OutputValue -Content $Output -Name "config"
    $agentPath = Get-OutputValue -Content $Output -Name "agent_exe"
    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        mode_listen = $Output.Contains("mode=listen")
        shared_pre_roll_runtime = $Output.Contains("listener_capture_lifecycle=shared_pre_roll_runtime")
        zero_session = $Output.Contains("max_sessions=0")
        completed_zero_sessions = $Output.Contains("listen_completed_sessions=0")
        config_path = $configPath
        config_path_present = ![string]::IsNullOrWhiteSpace($configPath)
        agent_path = $agentPath
        agent_path_present = ![string]::IsNullOrWhiteSpace($agentPath)
    }
}

function Get-ScriptParseProof {
    param(
        [string]$Output = ""
    )

    $count = Get-RomaWindowsScriptParseCount -Output $Output
    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        ok = $Output.Contains("windows_scripts_parse_ok=true")
        count_present = $Output.Contains("windows_scripts_parse_count=")
        count = $count
    }
}

function Get-ConfigDoctorOutputProof {
    param(
        [string]$Output = ""
    )

    $configPath = Get-OutputValue -Content $Output -Name "config"
    $transcriptionClient = Get-OutputValue -Content $Output -Name "transcription_client"
    return [ordered]@{
        output_present = ![string]::IsNullOrWhiteSpace($Output)
        config_path = $configPath
        config_path_present = ![string]::IsNullOrWhiteSpace($configPath)
        config_valid = $Output.Contains("config_valid=true")
        transcription_client = $transcriptionClient
        transcription_client_present = ![string]::IsNullOrWhiteSpace($transcriptionClient)
        uses_cloud = $Output.Contains("transcription_client=openai-compatible")
        api_key_resolved = $Output.Contains("api_key_resolved=true")
        uses_whisper_cli = $Output.Contains("transcription_client=whisper.cpp-cli")
        whisper_cli_exists = $Output.Contains("whisper_cli_exists=true")
        whisper_model_exists = $Output.Contains("whisper_model_exists=true")
    }
}

function Get-CurrentWindowsUserSid {
    if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
        return ""
    }

    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $identity -and $null -ne $identity.User) {
            return [string]$identity.User.Value
        }
    } catch {
        return ""
    }

    return ""
}

function Write-ProofReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Mode,
        [Parameter(Mandatory = $true)]
        [bool]$IsDoctorOnly
    )

    if ([string]::IsNullOrWhiteSpace($ProofReportPath)) {
        return
    }

    $reportParent = Split-Path -Parent $ProofReportPath
    if (![string]::IsNullOrWhiteSpace($reportParent)) {
        New-Item -ItemType Directory -Force -Path $reportParent | Out-Null
    }

    $shortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $shortcutPath = Join-Path $ShortcutDir "Roma Just Talk Agent.lnk"
    }
    $startupShortcutPath = ""
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $startupShortcutPath = Join-Path $StartupShortcutDir "Roma Just Talk Agent.lnk"
    } elseif ($CreateStartupShortcut) {
        $startup = [System.Environment]::GetFolderPath("Startup")
        if (![string]::IsNullOrWhiteSpace($startup)) {
            $startupShortcutPath = Join-Path $startup "Roma Just Talk Agent.lnk"
        }
    }
    $installedRunScriptPath = Join-Path $InstallDir "run-windows-agent.ps1"
    $fileProofs = [ordered]@{
        packaged_agent = (Get-FileHashProof -Path $agentPath)
        packaged_proof_agent = (Get-FileHashProof -Path $script:proofAgentPath)
        packaged_whisper_cli_mock = (Get-FileHashProof -Path $script:packagedWhisperCLI)
        installed_agent = (Get-FileHashProof -Path (Join-Path $InstallDir "RomaWindowsAgent.exe"))
        installed_proof_agent = (Get-FileHashProof -Path (Join-Path $InstallDir "RomaProofAgent.exe"))
    }
    Add-RomaWindowsProofFields `
        -Proof $fileProofs `
        -Fields (Get-RomaWindowsInstalledProofSurfaceFileProofs -InstallDir $InstallDir) |
        Out-Null

    $report = [ordered]@{
        generated_at = (Get-Date).ToUniversalTime().ToString("o")
        proof_session_id = $ProofSessionId
        proof_mode = $Mode
        doctor_only = $IsDoctorOnly
        run_dictation = $RunDictation.IsPresent
        paste_dictation = $PasteDictation.IsPresent
        expected_transcript_text = $ExpectedTranscriptText
        create_shortcut = $CreateShortcut.IsPresent
        create_startup_shortcut = $CreateStartupShortcut.IsPresent
        restore_clipboard = $RestoreClipboard.IsPresent
        no_restore_clipboard = $NoRestoreClipboard.IsPresent
        os = [ordered]@{
            platform = [System.Environment]::OSVersion.Platform.ToString()
            version = [System.Environment]::OSVersion.VersionString
            machine = $env:COMPUTERNAME
            user_name = $env:USERNAME
            user_domain = $env:USERDOMAIN
            user_sid = Get-CurrentWindowsUserSid
        }
        package_dir = $PackageDir
        install_dir = $InstallDir
        config = (Get-ConfigProof)
        doctor = [ordered]@{
            packaged_agent = (Get-DoctorOutputProof -Output $script:packagedAgentDoctorOutput)
            packaged_proof_agent = (Get-ProofAgentDoctorOutputProof -Output $script:packagedProofAgentDoctorOutput)
            packaged_native_doctors = [ordered]@{
                register_hotkey = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["register_hotkey"]) -ExpectedMarker "windows_hotkey_runtime=true")
                register_hotkey_available = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["register_hotkey_available"]) -ExpectedMarker "hotkey_registration_available=true")
                keyboard_hook = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["keyboard_hook"]) -ExpectedMarker "runtime=true")
                paste = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["paste"]) -ExpectedMarker "windows_paste_runtime=true")
                dpapi_secret = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["dpapi_secret"]) -ExpectedMarker "dpapi_runtime=true")
                miniaudio_capture = (Get-NativeDoctorOutputProof -Output ($script:packagedNativeDoctorOutputs["miniaudio_capture"]) -ExpectedMarker "native_capture_adapter=true")
            }
            installed_launcher = (Get-DoctorOutputProof -Output $script:installedLauncherDoctorOutput)
        }
        packaged_listener = (Get-ListenerSmokeProof -Output $script:packagedListenerOutput)
        installed_listener = (Get-ListenerSmokeProof -Output $script:installedListenerOutput)
        config_doctor = (Get-ConfigDoctorOutputProof -Output $script:installedConfigDoctorOutput)
        files = $fileProofs
        manifest = $script:artifactManifest
        package_identity = (Get-RomaPackageIdentityProof -PackageDir $PackageDir)
        installed_script_parse = (Get-ScriptParseProof -Output $script:installedScriptParseOutput)
    }
    if (![string]::IsNullOrWhiteSpace($shortcutPath)) {
        $report["shortcut"] = Get-ShortcutProof `
            -Path $shortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if (![string]::IsNullOrWhiteSpace($startupShortcutPath)) {
        $report["startup_shortcut"] = Get-ShortcutProof `
            -Path $startupShortcutPath `
            -RunScriptPath $installedRunScriptPath `
            -ConfigPath $ConfigPath `
            -WorkingDirectory $InstallDir
    }
    if ($RunDictation) {
        $report["dictation_runtime"] = Get-DictationRuntimeProof
    }
    if ($RunNotepadPasteProof) {
        $report["notepad_paste"] = $script:notepadPasteProof
    }

    $report |
        ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $ProofReportPath -Encoding UTF8
    Write-Host "proof_report=$ProofReportPath"
}

if ($UseHoldHook -and $UseToggle) {
    throw "UseHoldHook and UseToggle are mutually exclusive"
}

$hasExplicitClipboardRestoreDelay = $PSBoundParameters.ContainsKey("ClipboardRestoreDelaySeconds")

if ($RestoreClipboard -and $NoRestoreClipboard) {
    throw "RestoreClipboard and NoRestoreClipboard are mutually exclusive"
}

if ($NoRestoreClipboard -and $hasExplicitClipboardRestoreDelay) {
    throw "NoRestoreClipboard and ClipboardRestoreDelaySeconds are mutually exclusive"
}

if ($ClipboardRestoreDelaySeconds -lt 0) {
    throw "ClipboardRestoreDelaySeconds must be non-negative"
}

if ([string]::IsNullOrWhiteSpace($PackageDir)) {
    $PackageDir = $PSScriptRoot
}
$PackageDir = Resolve-FullPath -Path $PackageDir

if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw "LOCALAPPDATA is not set; pass -InstallDir explicitly"
    }
    $InstallDir = Join-Path $env:LOCALAPPDATA "roma-just-talk\agent"
}
$InstallDir = Resolve-FullPath -Path $InstallDir

if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Resolve-FullPath -Path $ConfigPath
}
if (![string]::IsNullOrWhiteSpace($ProofReportPath)) {
    $ProofReportPath = Resolve-FullPath -Path $ProofReportPath
}
if ([string]::IsNullOrWhiteSpace($NotepadPasteProofPath)) {
    $NotepadPasteProofPath = Join-Path $InstallDir "smoke\notepad-paste-proof.txt"
}
$NotepadPasteProofPath = Resolve-FullPath -Path $NotepadPasteProofPath

$agentPath = Join-Path $PackageDir "RomaWindowsAgent.exe"
$script:proofAgentPath = Join-Path $PackageDir "RomaProofAgent.exe"
$smokeScript = Join-Path $PackageDir "smoke-windows-agent.ps1"
$installScript = Join-Path $PackageDir "install-windows-agent.ps1"
$runScript = Join-Path $PackageDir "run-windows-agent.ps1"
$proofScript = Join-Path $PackageDir "prove-windows-agent-artifact.ps1"
$laptopProofScript = Join-Path $PackageDir "run-windows-laptop-proof.ps1"
$parseScript = Join-Path $PackageDir "check-windows-scripts-parse.ps1"
$packagedProofCommonScript = Join-Path $PackageDir "windows-proof-common.ps1"
$checkReportScript = Join-Path $PackageDir "check-windows-proof-report.ps1"
$checkSetScript = Join-Path $PackageDir "check-windows-proof-set.ps1"
$manifestPath = Join-Path $PackageDir "manifest.txt"
$script:artifactManifest = @{}
$script:packagedWhisperCLI = ""
$script:packagedAgentDoctorOutput = ""
$script:packagedProofAgentDoctorOutput = ""
$script:packagedListenerOutput = ""
$script:installedListenerOutput = ""
$script:installedScriptParseOutput = ""
$script:installedConfigDoctorOutput = ""
$script:packagedNativeDoctorOutputs = [ordered]@{
    register_hotkey = ""
    register_hotkey_available = ""
    keyboard_hook = ""
    paste = ""
    dpapi_secret = ""
    miniaudio_capture = ""
}
$script:installedLauncherDoctorOutput = ""
$script:notepadPasteProof = New-NotepadPasteProof

Invoke-Step "artifact files" {
    Require-File -Path $agentPath
    Require-File -Path $script:proofAgentPath
    Require-File -Path $smokeScript
    Require-File -Path $installScript
    Require-File -Path $runScript
    Require-File -Path $proofScript
    Require-File -Path $laptopProofScript
    Require-File -Path $parseScript
    Require-File -Path $packagedProofCommonScript
    Require-File -Path $checkReportScript
    Require-File -Path $checkSetScript
    Require-File -Path $manifestPath

    if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        Require-File -Path (Join-Path $PackageDir "swiftCore.dll")
    }
}

Invoke-Step "artifact manifest" {
    $script:artifactManifest = Read-RomaWindowsManifest -Path $manifestPath
    foreach ($key in @(
        "agent",
        "output",
        "proof_agent",
        "whisper_cli_mock",
        "smoke_script",
        "run_script",
        "install_script",
        "proof_script",
        "laptop_proof_script",
        "parse_script",
        "check_report_script",
        "check_set_script",
        "install_proof_config",
        "install_proof_shortcut",
        "local_whisper_install_config",
        "local_whisper_shortcut",
        "proof_common_script",
        "manifest_script",
        "package_identity_script",
        "swift_runtime_dlls"
    )) {
        Require-RomaWindowsManifestKey -Manifest $script:artifactManifest -Key $key
    }
    $script:packagedWhisperCLI = Require-RomaWindowsManifestFile `
        -Manifest $script:artifactManifest `
        -Key "whisper_cli_mock" `
        -BaseDir $PackageDir
    Write-Host "manifest_whisper_cli_mock_path=$script:packagedWhisperCLI"
    $script:proofAgentPath = Require-RomaWindowsManifestFile `
        -Manifest $script:artifactManifest `
        -Key "proof_agent" `
        -BaseDir $PackageDir
    Write-Host "manifest_proof_agent_path=$script:proofAgentPath"
}

if ($UsePackagedWhisperMock) {
    if (![string]::IsNullOrWhiteSpace($WhisperCLI) -or
        ![string]::IsNullOrWhiteSpace($WhisperModel) -or
        ![string]::IsNullOrWhiteSpace($Endpoint) -or
        ![string]::IsNullOrWhiteSpace($Model)) {
        throw "UsePackagedWhisperMock cannot be combined with explicit WhisperCLI/WhisperModel or Endpoint/Model"
    }

    $WhisperCLI = $script:packagedWhisperCLI
    $WhisperModel = $agentPath
    Write-Host "packaged_whisper_cli=$WhisperCLI"
    Write-Host "packaged_whisper_model=$WhisperModel"
}

Invoke-Step "packaged agent doctor" {
    $script:packagedAgentDoctorOutput = & $agentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedAgentDoctorOutput
        throw "RomaWindowsAgent doctor failed"
    }
    Write-Host $script:packagedAgentDoctorOutput
    Assert-RomaWindowsRuntimeDefaultOutput -Output $script:packagedAgentDoctorOutput
    Assert-RomaWindowsMinimumPermissionOutput -Output $script:packagedAgentDoctorOutput
}

Invoke-Step "packaged proof agent doctor" {
    $script:packagedProofAgentDoctorOutput = & $script:proofAgentPath doctor 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:packagedProofAgentDoctorOutput
        throw "RomaProofAgent doctor failed"
    }
    Write-Host $script:packagedProofAgentDoctorOutput
    Assert-RomaWindowsRuntimeDefaultOutput -Output $script:packagedProofAgentDoctorOutput
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_paste_adapter_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_dictation_runtime_uses_pipeline_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_listener_output_isolation_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_listener_pre_roll_runtime_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_hold_hook_single_window_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_dictation_proof_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "roma_transcription_client_source=true"
    Assert-OutputContains -Output $script:packagedProofAgentDoctorOutput -Expected "windows_proof_args_shared_source=true"
}

Invoke-Step "packaged listener smoke" {
    $script:packagedListenerOutput = Invoke-PackagedListenerSmoke -ConfigPath (Join-Path $PackageDir "sample-windows-agent.json")
}

Invoke-Step "packaged native proof doctors" {
    $script:packagedNativeDoctorOutputs["register_hotkey"] = Invoke-ProofAgentDoctorCommand -Name "register hotkey" -Command "windows-hotkey-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["register_hotkey"]) -Expected "windows_hotkey_runtime=true"

    $script:packagedNativeDoctorOutputs["register_hotkey_available"] = Invoke-ProofAgentDoctorCommand -Name "register hotkey availability" -Command "windows-hotkey-availability-proof"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["register_hotkey_available"]) -Expected "hotkey_registration_available=true"

    $script:packagedNativeDoctorOutputs["keyboard_hook"] = Invoke-ProofAgentDoctorCommand -Name "keyboard hook" -Command "windows-keyboard-hook-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["keyboard_hook"]) -Expected "runtime=true"
    Assert-RomaWindowsHoldTimeoutDefaultOutput -Output ($script:packagedNativeDoctorOutputs["keyboard_hook"])

    $script:packagedNativeDoctorOutputs["paste"] = Invoke-ProofAgentDoctorCommand -Name "paste" -Command "windows-paste-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["paste"]) -Expected "windows_paste_runtime=true"
    Assert-RomaWindowsClipboardRestoreDefaultOutput -Output ($script:packagedNativeDoctorOutputs["paste"])

    $script:packagedNativeDoctorOutputs["dpapi_secret"] = Invoke-ProofAgentDoctorCommand -Name "dpapi secret" -Command "windows-secret-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["dpapi_secret"]) -Expected "dpapi_runtime=true"

    $script:packagedNativeDoctorOutputs["miniaudio_capture"] = Invoke-ProofAgentDoctorCommand -Name "miniaudio capture" -Command "miniaudio-capture-doctor"
    Assert-OutputContains -Output ($script:packagedNativeDoctorOutputs["miniaudio_capture"]) -Expected "native_capture_adapter=true"
}

if ($DoctorOnly) {
    Write-ProofReport -Mode "doctor-only" -IsDoctorOnly $true
    Write-Host ""
    Write-Host "artifact_doctor_only=true"
    exit 0
}

$hasEndpoint = ![string]::IsNullOrWhiteSpace($Endpoint)
$hasModel = ![string]::IsNullOrWhiteSpace($Model)
$hasWhisperCLI = ![string]::IsNullOrWhiteSpace($WhisperCLI)
$hasWhisperModel = ![string]::IsNullOrWhiteSpace($WhisperModel)
$usesCloud = $hasEndpoint -or $hasModel
$usesWhisper = $hasWhisperCLI -or $hasWhisperModel

if ($usesCloud -and $usesWhisper) {
    throw "Endpoint/Model and WhisperCLI/WhisperModel are mutually exclusive"
}

if ($usesCloud -and (!$hasEndpoint -or !$hasModel)) {
    throw "Endpoint and Model must be provided together"
}

if ($usesWhisper -and (!$hasWhisperCLI -or !$hasWhisperModel)) {
    throw "WhisperCLI and WhisperModel must be provided together"
}

if (!$usesCloud -and !$usesWhisper) {
    throw "Pass cloud Endpoint/Model/API key, local WhisperCLI/WhisperModel, or -UsePackagedWhisperMock"
}

if ($usesCloud -and
    [string]::IsNullOrWhiteSpace($ApiKeyEnv) -and
    [string]::IsNullOrWhiteSpace($ApiKeyName)) {
    throw "Cloud proof requires ApiKeyEnv or ApiKeyName"
}

$proofMode = if ($UsePackagedWhisperMock) {
    "packaged-whisper-mock"
} elseif ($usesWhisper) {
    "local-whisper"
} else {
    "cloud"
}

if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    if (($usesCloud -or $usesWhisper -or $RunDictation) -and
        ![string]::IsNullOrWhiteSpace($env:APPDATA)) {
        $ConfigPath = Join-Path $env:APPDATA "roma-just-talk\windows-agent.json"
    } else {
        $ConfigPath = Join-Path $InstallDir "smoke\windows-agent-smoke.json"
    }
    $ConfigPath = Resolve-FullPath -Path $ConfigPath
}

$installArgs = @(
    "-PackageDir", $PackageDir,
    "-InstallDir", $InstallDir
)
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    $installArgs += @("-ConfigPath", $ConfigPath)
}
if ($usesWhisper) {
    $installArgs += @("-WhisperCLI", $WhisperCLI, "-WhisperModel", $WhisperModel)
    if (![string]::IsNullOrWhiteSpace($WhisperOutputDir)) {
        $installArgs += @("-WhisperOutputDir", $WhisperOutputDir)
    }
    $whisperArguments = @(
        $WhisperArgument |
            Where-Object { ![string]::IsNullOrWhiteSpace($_) }
    )
    if ($whisperArguments.Count -gt 0) {
        $installArgs += "-WhisperArgument"
        $installArgs += $whisperArguments
    }
} else {
    $installArgs += @("-Endpoint", $Endpoint, "-Model", $Model)
    if (![string]::IsNullOrWhiteSpace($ApiKeyEnv)) {
        $installArgs += @("-ApiKeyEnv", $ApiKeyEnv)
    }
    if (![string]::IsNullOrWhiteSpace($ApiKeyName)) {
        $installArgs += @("-ApiKeyName", $ApiKeyName)
    }
    if (![string]::IsNullOrWhiteSpace($SecretDir)) {
        $installArgs += @("-SecretDir", $SecretDir)
    }
}
$installArgs = Add-RomaWindowsAgentScriptCommonArgs `
    -ArgumentList $installArgs `
    -Language $Language `
    -Prompt $Prompt `
    -WordReplacement $WordReplacement `
    -UseHoldHook $UseHoldHook.IsPresent `
    -UseToggle $UseToggle.IsPresent `
    -HoldTimeoutSeconds $HoldTimeoutSeconds `
    -RecordSeconds $RecordSeconds `
    -PasteDictation $PasteDictation.IsPresent `
    -RestoreClipboard $RestoreClipboard.IsPresent `
    -NoRestoreClipboard $NoRestoreClipboard.IsPresent `
    -HasClipboardRestoreDelay $hasExplicitClipboardRestoreDelay `
    -ClipboardRestoreDelaySeconds $ClipboardRestoreDelaySeconds
if ($RunDictation) {
    $installArgs += "-RunDictation"
}
if ($CreateShortcut) {
    $installArgs += "-CreateShortcut"
    if (![string]::IsNullOrWhiteSpace($ShortcutDir)) {
        $installArgs += @("-ShortcutDir", $ShortcutDir)
    }
}
if ($CreateStartupShortcut) {
    $installArgs += "-CreateStartupShortcut"
    if (![string]::IsNullOrWhiteSpace($StartupShortcutDir)) {
        $installArgs += @("-StartupShortcutDir", $StartupShortcutDir)
    }
}

Invoke-Step "install packaged agent" {
    & $installScript @installArgs
}

Invoke-Step "installed script parse check" {
    $installedParseScript = Join-Path $InstallDir "check-windows-scripts-parse.ps1"
    Require-File -Path $installedParseScript
    $script:installedScriptParseOutput = & $installedParseScript -ScriptsDir $InstallDir 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:installedScriptParseOutput
        throw "Installed script parse check failed"
    }
    Write-Host $script:installedScriptParseOutput
    Assert-RomaWindowsScriptParseCount `
        -Output $script:installedScriptParseOutput `
        -ExpectedCount (Get-RomaWindowsInstalledProofSurfaceScriptCount) `
        -Name "installed"
}

Invoke-Step "installed launcher doctor" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $runArgs = @(
        "-InstallDir", $InstallDir,
        "-DoctorOnly"
    )
    if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
        $runArgs += @("-ConfigPath", $ConfigPath)
    }
    $script:installedLauncherDoctorOutput = & $installedRun @runArgs 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Host $script:installedLauncherDoctorOutput
        throw "Installed launcher doctor failed"
    }
    Write-Host $script:installedLauncherDoctorOutput
}

Invoke-Step "installed config doctor" {
    $installedAgent = Join-Path $InstallDir "RomaWindowsAgent.exe"
    $script:installedConfigDoctorOutput = Invoke-ConfigDoctor `
        -AgentPath $installedAgent `
        -ConfigPath $ConfigPath
}

Invoke-Step "installed listener smoke" {
    $installedRun = Join-Path $InstallDir "run-windows-agent.ps1"
    Require-File -Path $installedRun
    $script:installedListenerOutput = Invoke-InstalledListenerSmoke `
        -RunScriptPath $installedRun `
        -ConfigPath $ConfigPath
}

if ($RunNotepadPasteProof) {
    Invoke-Step "notepad paste proof" {
        $script:notepadPasteProof = Invoke-NotepadPasteProof
    }
}

Write-ProofReport -Mode $proofMode -IsDoctorOnly $false

Write-Host ""
Write-Host "artifact_proof=ok"
Write-Host "package_dir=$PackageDir"
Write-Host "install_dir=$InstallDir"
if (![string]::IsNullOrWhiteSpace($ConfigPath)) {
    Write-Host "config=$ConfigPath"
}
