#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$Arguments = @($args)

function Show-Usage {
    @'
Usage:
  agent [options] [--] [command...]
  agent build [docker-build-options...]
  agent exec [command...]
  agent stop
  agent status
  agent list

Commands:
  codex, claude, opencode  Start a coding agent in the workspace container.
                           Codex defaults to --sandbox danger-full-access and
                           Claude Code and OpenCode to
                           --dangerously-skip-permissions, because the
                           container is the isolation boundary.
  build [OPTIONS...]       Build the image; pass options to docker build.
  codex-ssh                Open the Codex authentication SSH tunnel.
  exec [COMMAND...]        Run a command in the current workspace container.
  stop                     Stop the current workspace container.
  status                   Show the current workspace container.
  list, ls                 List all running agent containers.

Options:
  -p, --port PORT          Publish a port (for example 3000 or 8080:3000).
  --ssh-port PORT          Host port mapped to container SSH port 22.
  --codex-port PORT        Host port mapped to the Codex callback port 1455.
  --no-codex-auth          Disable Codex authentication ports and sshd.
  --credentials DIR        Mount supported credentials read-write.
  --credentials-ro DIR     Mount supported credentials read-only.
  --docker-arg ARG         Pass one additional argument to docker run.
  -h, --help               Show this help.

Environment:
  AI_AGENT_HOME            State directory (default: ~/.agent-container).
  AI_AGENT_IMAGE           Image name (default: agent-container:latest).
  AI_AGENT_SSH_PORT        Preferred Codex SSH port.
  AI_AGENT_CODEX_PORT      Codex callback host port (default: 1455).
'@ | Write-Output
}

function Assert-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker was not found. Install and start Docker Desktop, then try again.'
    }
}

function Get-MatchingContainer {
    param([switch] $IncludeStopped)

    $dockerArguments = if ($IncludeStopped) { @('ps', '-a') } else { @('ps') }
    $result = & docker @dockerArguments `
        --filter 'label=agent-container=true' `
        --filter "label=agent-workspace=$script:WorkspaceId" `
        --format '{{.ID}}'
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to query Docker. Make sure Docker Desktop is running.'
    }
    return @($result)[0]
}

function Get-RunningContainer {
    $container = Get-MatchingContainer
    if (-not $container) {
        throw "No running agent container found for:`n  $script:Workspace"
    }
    return $container
}

function Test-PortAvailable {
    param([int] $Port)

    $listener = $null
    try {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
        $listener.Start()
        return $true
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        if ($listener) { $listener.Stop() }
    }
}

function Test-GitSymlinkPlaceholder {
    param(
        [string] $Path,
        [string] $ExpectedTarget
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        return (Get-Content -LiteralPath $Path -Raw).Trim() -eq $ExpectedTarget
    }
    catch {
        return $false
    }
}

function Get-SshPort {
    if ($script:SshHostPort) { return $script:SshHostPort }
    foreach ($port in 2222..2299) {
        if (Test-PortAvailable $port) { return $port }
    }
    throw 'Unable to find an available SSH host port between 2222 and 2299.'
}

function Invoke-AgentBuild {
    param([string[]] $DockerBuildArguments = @())

    $environmentFile = Join-Path $script:AgentHome 'versions.env'
    $buildArguments = [System.Collections.Generic.List[string]]::new()

    if (Test-Path -LiteralPath $environmentFile -PathType Leaf) {
        foreach ($line in Get-Content -LiteralPath $environmentFile) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith('#')) { continue }
            if ($trimmed -notmatch '^[^=]+=') {
                throw "Invalid entry in ${environmentFile}: $line"
            }
            $buildArguments.Add('--build-arg')
            $buildArguments.Add($trimmed)
        }
    }

    $arguments = @('build') + $buildArguments.ToArray() + $DockerBuildArguments + @('--tag', $script:Image, $script:AgentHome)
    & docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker image build failed with exit code $LASTEXITCODE." }
}

function Assert-AgentImage {
    & docker image inspect $script:Image 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { return }

    Write-Output "Docker image '$($script:Image)' is not built."
    if ([Console]::IsInputRedirected) {
        throw "Run 'agent build' to build it, then try again."
    }

    $response = Read-Host 'Build it now? [Y/n]'
    if (-not $response -or $response -match '^(?i:y|yes)$') {
        Invoke-AgentBuild
        return
    }

    throw "Build cancelled. Run 'agent build' when you are ready."
}

function Invoke-Docker {
    param([string[]] $DockerArguments)
    & docker @DockerArguments
    exit $LASTEXITCODE
}

try {
    $script:AgentHome = if ($env:AI_AGENT_HOME) {
        [System.IO.Path]::GetFullPath($env:AI_AGENT_HOME)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $HOME '.agent-container'))
    }
    $script:Image = if ($env:AI_AGENT_IMAGE) { $env:AI_AGENT_IMAGE } else { 'agent-container:latest' }
    $script:SshHostPort = $env:AI_AGENT_SSH_PORT
    $CodexHostPort = if ($env:AI_AGENT_CODEX_PORT) { $env:AI_AGENT_CODEX_PORT } else { '1455' }
    $script:Workspace = (Get-Item -LiteralPath (Get-Location).Path).FullName
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:Workspace))
    $sha256.Dispose()
    $script:WorkspaceId = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    $script:WorkspaceId = $script:WorkspaceId.Substring(0, 12)
    $ContainerName = "agent-$($script:WorkspaceId)"

    $ExtraPorts = [System.Collections.Generic.List[string]]::new()
    $DockerRunArguments = [System.Collections.Generic.List[string]]::new()
    $Command = [System.Collections.Generic.List[string]]::new()
    $CredentialsDirectory = $null
    $CredentialsReadOnly = $false
    $CredentialsRequested = $false
    $CodexAuthEnabled = $true

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]
        switch -Regex ($argument) {
            '^(-p|--port)$' {
                if (++$index -ge $Arguments.Count) { throw "Missing value for $argument" }
                $ExtraPorts.Add($Arguments[$index]); continue
            }
            '^--ssh-port$' {
                if (++$index -ge $Arguments.Count) { throw 'Missing value for --ssh-port' }
                $script:SshHostPort = $Arguments[$index]; continue
            }
            '^--codex-port$' {
                if (++$index -ge $Arguments.Count) { throw 'Missing value for --codex-port' }
                $CodexHostPort = $Arguments[$index]; continue
            }
            '^--no-codex-auth$' { $CodexAuthEnabled = $false; continue }
            '^--credentials(-ro)?$' {
                if (++$index -ge $Arguments.Count) { throw "Missing value for $argument" }
                if ($CredentialsRequested) { throw 'Specify only one of --credentials or --credentials-ro.' }
                $CredentialsRequested = $true
                $CredentialsReadOnly = $argument -eq '--credentials-ro'
                $CredentialsDirectory = $Arguments[$index]
                continue
            }
            '^--docker-arg$' {
                if (++$index -ge $Arguments.Count) { throw 'Missing value for --docker-arg' }
                $DockerRunArguments.Add($Arguments[$index]); continue
            }
            '^(-h|--help)$' { Show-Usage; exit 0 }
            '^--$' {
                for ($index++; $index -lt $Arguments.Count; $index++) { $Command.Add($Arguments[$index]) }
                break
            }
            default {
                for (; $index -lt $Arguments.Count; $index++) { $Command.Add($Arguments[$index]) }
                break
            }
        }
        if ($Command.Count -gt 0 -or $argument -eq '--') { break }
    }

    Assert-DockerAvailable

    $builtIn = if ($Command.Count) { $Command[0] } else { '' }
    if ($CredentialsRequested -and $builtIn -in @('build', 'exec', 'stop', 'status', 'list', 'ls')) {
        throw "Credential options cannot be used with 'agent $builtIn'; they only apply when creating a container."
    }

    if ($builtIn -eq 'build') {
        $buildOptions = if ($Command.Count -gt 1) { $Command.GetRange(1, $Command.Count - 1).ToArray() } else { @() }
        Invoke-AgentBuild $buildOptions
        exit 0
    }

    if ($builtIn -eq 'codex-ssh') {
        if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
            throw 'OpenSSH Client is required. Install it from Windows Optional Features.'
        }
        $containers = & docker ps --filter 'label=agent-container=true' --filter 'publish=1455' --format '{{.ID}}'
        $sshPort = $null
        foreach ($container in $containers) {
            $sshPort = & docker inspect --format '{{with index .NetworkSettings.Ports "22/tcp"}}{{(index . 0).HostPort}}{{end}}' $container
            if ($sshPort) { break }
        }
        if (-not $sshPort) { throw 'No running agent container publishes the Codex callback port.' }
        if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
            & ssh-keygen -R "[localhost]:$sshPort" 2>$null | Out-Null
        }
        & ssh -p $sshPort -L 1455:localhost:1455 root@localhost
        exit $LASTEXITCODE
    }

    if ($builtIn -eq 'exec') {
        $container = Get-RunningContainer
        $execArguments = @('exec', '--interactive')
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $execArguments += '--tty' }
        $execArguments += @('--workdir', '/workspace', $container)
        if ($Command.Count -eq 1) { $execArguments += 'bash' } else { $execArguments += $Command.GetRange(1, $Command.Count - 1) }
        Invoke-Docker $execArguments
    }

    if ($builtIn -eq 'stop') {
        $container = Get-MatchingContainer
        if (-not $container) { Write-Output "No running agent container for:`n  $script:Workspace"; exit 0 }
        Write-Output "Stopping agent container $container"
        Invoke-Docker @('stop', $container)
    }

    if ($builtIn -eq 'status') {
        $container = Get-MatchingContainer
        if (-not $container) { Write-Output "No agent container is running for:`n  $script:Workspace"; exit 1 }
        Write-Output 'Agent container is running:'
        Invoke-Docker @('ps', '--filter', "id=$container", '--format', "  ID:       {{.ID}}`n  Name:     {{.Names}}`n  Image:    {{.Image}}`n  Status:   {{.Status}}`n  Ports:    {{.Ports}}")
    }

    if ($builtIn -in @('list', 'ls')) {
        $listFormat = "ID: {{.ID}}`tName: {{.Names}}`tImage: {{.Image}}`tStatus: {{.Status}}`tPorts: {{.Ports}}`tPWD: {{.Label `"agent-workspace-path`"}}"
        Invoke-Docker @('ps', '--filter', 'label=agent-container=true', '--format', $listFormat)
    }

    $runningContainer = Get-MatchingContainer
    if (-not $Command.Count -and $runningContainer) {
        if ($CredentialsRequested) { throw 'Credential mounts require a new container. Run agent stop first.' }
        Write-Output "Attaching to agent container $runningContainer"
        $execArguments = @('exec', '--interactive')
        if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $execArguments += '--tty' }
        $execArguments += @('--workdir', '/workspace', $runningContainer, 'bash')
        Invoke-Docker $execArguments
    }
    if ($runningContainer) {
        throw "An agent container is already running for this workspace:`n  $script:Workspace`nUse 'agent', 'agent exec <command>', or 'agent stop'."
    }


    Assert-AgentImage

    $CredentialMountArguments = [System.Collections.Generic.List[string]]::new()
    if ($CredentialsRequested) {
        if (-not (Test-Path -LiteralPath $CredentialsDirectory -PathType Container)) {
            throw "Credential profile is not a directory: $CredentialsDirectory"
        }
        $CredentialsDirectory = (Get-Item -LiteralPath $CredentialsDirectory).FullName
        $credentialPaths = @(
            @{ Host = Join-Path $CredentialsDirectory '.ssh'; Container = '/root/.ssh' },
            @{ Host = Join-Path $CredentialsDirectory '.config/gh'; Container = '/root/.config/gh' }
        )
        foreach ($credentialPath in $credentialPaths) {
            if (Test-Path -LiteralPath $credentialPath.Host) {
                if (-not (Test-Path -LiteralPath $credentialPath.Host -PathType Container)) {
                    throw "Credential path is not a directory: $($credentialPath.Host)"
                }
                $suffix = if ($CredentialsReadOnly) { ':ro' } else { '' }
                $CredentialMountArguments.Add('--volume')
                $CredentialMountArguments.Add("$($credentialPath.Host):$($credentialPath.Container)$suffix")
            }
        }
        if (-not $CredentialMountArguments.Count) {
            throw "Credential profile contains no .ssh or .config/gh directory: $CredentialsDirectory"
        }
    }

    $existingContainer = Get-MatchingContainer -IncludeStopped
    if ($existingContainer) {
        & docker rm $existingContainer | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Unable to remove stale container $existingContainer." }
    }

    $PublishSsh = $false
    $PublishCodex = $false
    if ($Command.Count -and $Command[0] -eq 'codex') {
        if (Test-Path -LiteralPath (Join-Path $script:AgentHome '.codex/auth.json') -PathType Leaf) {
            $CodexAuthEnabled = $false
        }
        $sandboxConfigured = $false
        foreach ($argument in @($Command | Select-Object -Skip 1)) {
            if ($argument -eq '--sandbox' -or $argument -eq '-s' -or $argument -like '--sandbox=*' -or
                $argument -like '-s?*' -or $argument -in @('--dangerously-bypass-approvals-and-sandbox', '--yolo')) {
                $sandboxConfigured = $true; break
            }
        }
        if (-not $sandboxConfigured) {
            $remainingCommand = @($Command | Select-Object -Skip 1)
            $Command = [System.Collections.Generic.List[string]]::new()
            @('codex', '--sandbox', 'danger-full-access') + $remainingCommand | ForEach-Object { $Command.Add($_) }
        }
        if ($CodexAuthEnabled) { $PublishSsh = $true; $PublishCodex = $true }
    }

    if ($Command.Count -and $Command[0] -eq 'claude') {
        $permissionsConfigured = $false
        foreach ($argument in @($Command | Select-Object -Skip 1)) {
            if ($argument -eq '--permission-mode' -or $argument -like '--permission-mode=*' -or
                $argument -in @('--dangerously-skip-permissions', '--allow-dangerously-skip-permissions')) {
                $permissionsConfigured = $true; break
            }
        }
        if (-not $permissionsConfigured) {
            $remainingCommand = @($Command | Select-Object -Skip 1)
            $Command = [System.Collections.Generic.List[string]]::new()
            @('claude', '--dangerously-skip-permissions') + $remainingCommand | ForEach-Object { $Command.Add($_) }
        }
    }

    if ($Command.Count -and $Command[0] -eq 'opencode') {
        $permissionsConfigured = $false
        foreach ($argument in @($Command | Select-Object -Skip 1)) {
            if ($argument -in @('--auto', '--yolo', '--dangerously-skip-permissions')) {
                $permissionsConfigured = $true; break
            }
        }
        if (-not $permissionsConfigured) {
            $remainingCommand = @($Command | Select-Object -Skip 1)
            $Command = [System.Collections.Generic.List[string]]::new()
            @('opencode', '--dangerously-skip-permissions') + $remainingCommand | ForEach-Object { $Command.Add($_) }
        }
    }

    $stateDirectories = @('.codex', '.claude', '.config/opencode', '.local/share/opencode')
    foreach ($relativePath in $stateDirectories) {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:AgentHome $relativePath) | Out-Null
    }

    $runArguments = [System.Collections.Generic.List[string]]::new()
    @('run', '--rm', '--interactive') | ForEach-Object { $runArguments.Add($_) }
    if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $runArguments.Add('--tty') }
    @(
        '--init', '--name', $ContainerName,
        '--label', 'agent-container=true',
        '--label', "agent-workspace=$($script:WorkspaceId)",
        '--label', "agent-workspace-path=$($script:Workspace)",
        '--add-host', 'host.docker.internal:host-gateway',
        '--workdir', '/workspace',
        # Claude Code refuses --dangerously-skip-permissions as root unless it
        # is told the surrounding environment is already a sandbox.
        '--env', 'IS_SANDBOX=1',
        '--volume', "$($script:Workspace):/workspace",
        '--volume', "$(Join-Path $script:AgentHome '.codex'):/root/.codex",
        '--volume', "$(Join-Path $script:AgentHome '.claude'):/root/.claude",
        '--volume', "$(Join-Path $script:AgentHome '.config/opencode'):/root/.config/opencode",
        '--volume', "$(Join-Path $script:AgentHome '.local/share/opencode'):/root/.local/share/opencode"
    ) | ForEach-Object { $runArguments.Add($_) }

    # Git for Windows may check symlinks out as files containing only their
    # target. Overlay the canonical instructions in that case without changing
    # the host checkout.
    $canonicalInstructions = Join-Path $script:AgentHome '.codex/AGENTS.md'
    $claudeInstructions = Join-Path $script:AgentHome '.claude/CLAUDE.md'
    $openCodeInstructions = Join-Path $script:AgentHome '.config/opencode/AGENTS.md'
    if ((Test-Path -LiteralPath $canonicalInstructions -PathType Leaf) -and
        (Test-GitSymlinkPlaceholder $claudeInstructions '../.codex/AGENTS.md')) {
        @('--volume', "${canonicalInstructions}:/root/.claude/CLAUDE.md:ro") |
            ForEach-Object { $runArguments.Add($_) }
    }
    if ((Test-Path -LiteralPath $canonicalInstructions -PathType Leaf) -and
        (Test-GitSymlinkPlaceholder $openCodeInstructions '../../.codex/AGENTS.md')) {
        @('--volume', "${canonicalInstructions}:/root/.config/opencode/AGENTS.md:ro") |
            ForEach-Object { $runArguments.Add($_) }
    }

    $CredentialMountArguments | ForEach-Object { $runArguments.Add($_) }
    if (-not $CodexAuthEnabled) { @('--env', 'CODEX_AUTH_ENABLED=0') | ForEach-Object { $runArguments.Add($_) } }
    if ($PublishSsh) {
        $resolvedSshPort = Get-SshPort
        @('--publish', "127.0.0.1:${resolvedSshPort}:22") | ForEach-Object { $runArguments.Add($_) }
        Write-Output "SSH:   localhost:$resolvedSshPort -> container:22"
    }
    if ($PublishCodex) {
        @('--publish', "127.0.0.1:${CodexHostPort}:1455") | ForEach-Object { $runArguments.Add($_) }
        Write-Output "Codex: localhost:$CodexHostPort -> container:1455"
    }
    foreach ($port in $ExtraPorts) {
        if ($port -notmatch ':') { $port = "${port}:${port}" }
        @('--publish', $port) | ForEach-Object { $runArguments.Add($_) }
    }
    $DockerRunArguments | ForEach-Object { $runArguments.Add($_) }
    $runArguments.Add($script:Image)
    $Command | ForEach-Object { $runArguments.Add($_) }
    Invoke-Docker $runArguments.ToArray()
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
