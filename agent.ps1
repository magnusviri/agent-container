#requires -Version 5.1

$ErrorActionPreference = 'Stop'
$Arguments = @($args)

function Show-Usage {
    @'
Usage:
  agent [options] [--] [command...]
  agent init
  agent build [docker-build-options...]
  agent ralph init
  agent ralph --tool <codex|claude|opencode> [max_iterations]
  agent exec [command...]
  agent root [command...]
  agent stop
  agent delete
  agent status
  agent list

Behavior:
  agent
      If a container is already running for the current directory, attach to
      it with an interactive shell.

      If no container is running but a stopped container exists, start it.
      When the last interactive terminal exits, the container is stopped.
      The launcher then asks whether to keep or delete the stopped container.

      If no container exists, start a new container with a shell.

      If the configured image does not exist, offer to build it before starting
      the container.

  agent build [OPTIONS...]
      Build the configured agent image. Options are passed to docker build.

  agent init
      Install shortcuts for the launcher itself.

      Creates 'agent' and 'agent-container' shortcuts in:

        ~/.agent-container/bin

      and appends that directory to the user PATH. Run it again to refresh the
      shortcuts and PATH entry.

  agent codex
      Start Codex in a new agent container.

      Codex defaults to --sandbox danger-full-access because the container
      provides the outer isolation boundary. Pass --sandbox or -s to override.

  agent tunnel
      Open the configured SSH tunnels to the running workspace container.

      The SSH host port and forwarded ports are read from the container. Exits
      with an error if the container was not created with --forward-port.

  agent claude
      Start Claude Code.

      Claude Code defaults to --dangerously-skip-permissions because the
      container provides the outer isolation boundary. Pass --permission-mode,
      --dangerously-skip-permissions, or --allow-dangerously-skip-permissions
      after claude to override.

      Every container sets IS_SANDBOX=1, which is what lets Claude Code accept
      that flag. The container runs as the unprivileged 'agent' user rather
      than root.

  agent opencode
      Start OpenCode.

      OpenCode defaults to --dangerously-skip-permissions because the
      container provides the outer isolation boundary. Pass --auto, --yolo,
      or --dangerously-skip-permissions after opencode to override.

  agent ralph
      Start the fresh-context Ralph loop in the workspace container.

      Use 'agent ralph init' once to create the workspace instruction, task,
      and progress files. Select an agent with --tool. If the workspace
      container is already running, Ralph starts inside that container.

  agent exec COMMAND...
      Execute COMMAND as the unprivileged 'agent' user inside the running
      agent container for the current workspace.

      Examples:
        agent exec bash
        agent exec git status
        agent exec npm test
        agent exec bundle exec rspec

  agent root COMMAND...
      Execute COMMAND as root inside the running agent container for the
      current workspace. If COMMAND is omitted, open an interactive root shell.

      This is a host-side maintenance command intended for tasks such as
      installing system packages. It does not install sudo or grant the
      in-container 'agent' user permission to become root.

      Examples:
        agent root
        agent root apt-get update
        agent root apt-get install -y PACKAGE

  agent stop
      Stop the running agent container for the current workspace.

  agent delete
      Delete the agent container for the current workspace, if it exists.

      Works whether the container is running or stopped.

  agent status
      Show whether an agent container is running for the current workspace.

  agent list
      List running agent containers with their IDs, names, images, statuses,
      ports, and host workspace paths.

Options:
  -p, --port PORT
      Publish an additional port.

      Examples:
        -p 3000
        -p 3000:3000
        -p 8080:3000
        -p 127.0.0.1:3000:3000

      A single port such as:

        -p 3000

      is interpreted as:

        -p 3000:3000

      Docker fixes published ports when a container is created. For an existing
      container, the requested mapping must already be configured. Otherwise,
      delete the container first:

        agent delete
        agent -p 3000 [command...]

      When a new container would have no published ports, the launcher asks
      for confirmation because ports cannot be added later.

  --ssh-port PORT
      Host port to map to container SSH port 22.

      This is published when at least one --forward-port is supplied. If
      omitted, the launcher chooses the first available port starting at 2222.

  --forward-port PORT
      Forward a port from your computer through SSH to the container.

      PORT forwards the same local and container port. LOCAL:CONTAINER uses a
      different local port. This option can be repeated.

      Examples:
        --forward-port 1455
        --forward-port 8080:3000

      The launcher starts sshd, publishes its SSH port on 127.0.0.1, and prints
      the ssh command to run on your computer. The forwarded service ports are
      carried inside the SSH connection and are not published by Docker.

  --credentials DIR
      Share credentials from a home-style profile directory, read-write.

      Supported directories are mounted when present:
        DIR/.ssh       -> /home/agent/.ssh
        DIR/.config/gh -> /home/agent/.config/gh

  --credentials-ro DIR
      Share the same supported credential directories read-only.

      Credential sharing only applies when creating a new container. It is
      never enabled by default.

  --docker-arg ARG
      Pass an additional argument directly to docker run.

      Can be specified multiple times.

      Example:
        agent --docker-arg --privileged codex

  -v, --verbose
      Print every docker command the launcher runs, quoted so it can be copied
      and rerun as-is, plus notes about launcher decisions.

      Output goes to stderr.

  -h, --help
      Show this help.

Environment:
  AI_AGENT_HOME
      Agent configuration and persistent-state directory.

      Default:
        ~/.agent-container

  AI_AGENT_IMAGE
      Docker image to run.

      Default:
        agent-container:latest

  AI_AGENT_SSH_PORT
      Preferred host SSH port when --forward-port is used.

      If unset, the launcher automatically finds an available port.

  AI_AGENT_FORWARD_PORT
      One SSH-forwarded port, in PORT or LOCAL:CONTAINER form.

  AI_AGENT_VERBOSE
      Set to 1 to enable verbose command logging without passing --verbose.

Persistent state:
  The following directories are mounted into every agent container:

    ~/.agent-container/.codex
        -> /home/agent/.codex

    ~/.agent-container/.claude
        -> /home/agent/.claude

    ~/.agent-container/.config/opencode
        -> /home/agent/.config/opencode

    ~/.agent-container/.local/share/opencode
        -> /home/agent/.local/share/opencode

Workspace:
  The current directory is mounted at:

    /workspace

Examples:
  agent init

  agent

  agent codex

  agent claude

  agent opencode

  agent ralph init

  agent ralph --tool codex

  agent ralph --tool claude 20

  agent ralph --tool opencode

  agent -p 3000 codex

  agent -p 3000 -p 5173 claude

  agent --verbose -p 3000 claude

  agent --ssh-port 2222 codex

  agent --forward-port 1455 codex

  agent --credentials "$HOME/.agent-credentials/work" codex

  agent --credentials-ro "$HOME/.agent-credentials/personal" claude

  agent exec bash

  agent exec git status

  agent exec npm test

  agent root

  agent root apt-get install -y PACKAGE

  agent status

  agent stop

  agent delete
'@ | Write-Output
}

function Write-CommandLog {
    param([string[]] $CommandArguments)

    if (-not $script:VerboseLogging) { return }
    $quoted = $CommandArguments | ForEach-Object {
        if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '\"') + '"' } else { $_ }
    }
    [Console]::Error.WriteLine("+ docker $($quoted -join ' ')")
}

function Write-VerboseNote {
    param([string] $Message)

    if (-not $script:VerboseLogging) { return }
    [Console]::Error.WriteLine("# $Message")
}

# Docker fixes published ports when a container is created. Reusing or attaching
# with -p is valid only when each requested mapping is already configured.
function Get-RequestedPortSummary {
    param([string[]] $Ports)

    return (($Ports | ForEach-Object { "  -p $_" }) -join "`n")
}

function Test-RequestedPortsConfigured {
    param(
        [string] $Container,
        [string[]] $Ports
    )

    Write-CommandLog @('inspect', '--format', '{{json .HostConfig.PortBindings}}', $Container)
    $json = & docker inspect --format '{{json .HostConfig.PortBindings}}' $Container
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect container $Container." }
    $bindings = $json | ConvertFrom-Json
    $script:MissingPorts = [System.Collections.Generic.List[string]]::new()

    foreach ($requested in $Ports) {
        $parts = @($requested -split ':')
        $containerSpec = $parts[-1]
        $containerParts = @($containerSpec -split '/', 2)
        $containerPort = $containerParts[0]
        $protocol = if ($containerParts.Count -gt 1) { $containerParts[1] } else { 'tcp' }

        if ($parts.Count -eq 1) {
            $hostPort = $containerPort
            $hostIp = $null
        } else {
            $hostPort = $parts[-2]
            $hostIp = if ($parts.Count -gt 2) { ($parts[0..($parts.Count - 3)] -join ':') } else { $null }
        }

        $property = $bindings.PSObject.Properties | Where-Object Name -CEQ "${containerPort}/${protocol}"
        $matched = $false
        if ($property) {
            foreach ($binding in @($property.Value)) {
                $ipMatches = $null -eq $hostIp -or $binding.HostIp -ceq $hostIp -or
                    ($hostIp -eq '0.0.0.0' -and -not $binding.HostIp)
                if ($binding.HostPort -ceq $hostPort -and $ipMatches) {
                    $matched = $true
                    break
                }
            }
        }
        if (-not $matched) { $script:MissingPorts.Add($requested) }
    }

    return -not $script:MissingPorts.Count
}

function Test-RequestedForwardsConfigured {
    param(
        [string] $Container,
        [string[]] $Ports
    )

    $expected = $Ports -join ','
    $labelArguments = @('inspect', '--format', '{{index .Config.Labels "agent-forward-ports"}}', $Container)
    Write-CommandLog $labelArguments
    $configured = & docker @labelArguments
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect container $Container." }

    $sshArguments = @('inspect', '--format', '{{with index .NetworkSettings.Ports "22/tcp"}}{{(index . 0).HostPort}}{{end}}', $Container)
    Write-CommandLog $sshArguments
    $sshPort = & docker @sshArguments
    if ($LASTEXITCODE -ne 0) { throw "Unable to inspect container $Container." }

    return $configured -ceq $expected -and [bool] $sshPort
}

function Throw-ForwardsRequireNewContainer {
    throw "This container is already created without the requested SSH forwards.`nDelete it and start over with the forwarding option:`n  agent delete`n  agent --forward-port PORT [command...]"
}

function Throw-PortsRequireNewContainer {
    throw "This container is already created, and its port configuration cannot be changed.`nIt does not publish:`n$(Get-RequestedPortSummary $script:MissingPorts)`n`nDelete the container and start over with the port option:`n  agent delete`n  agent -p PORT [command...]"
}

function Write-PublishedPorts {
    param([string] $Container)

    Write-CommandLog @('port', $Container)
    $ports = @(& docker port $Container)
    if ($LASTEXITCODE -ne 0) { throw "Unable to query published ports for container $Container." }
    Write-Output 'Published ports:'
    if ($ports.Count) {
        $ports | ForEach-Object { Write-Output "  $_" }
    } else {
        Write-Output '  (none)'
    }
}

function Confirm-NoPublishedPorts {
    $response = Read-Host "Are you sure you don't want to publish any ports? Once created, ports cannot be added later. [y/N]"
    if ($response -notmatch '^(?i:y|yes)$') {
        throw 'Cancelled.'
    }
}

function Assert-DockerAvailable {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'Docker was not found. Install and start Docker Desktop, then try again.'
    }
}

function Get-MatchingContainer {
    param([switch] $IncludeStopped)

    $dockerArguments = @('ps')
    if ($IncludeStopped) { $dockerArguments += '-a' }
    $dockerArguments += @(
        '--filter', 'label=agent-container=true',
        '--filter', "label=agent-workspace=$script:WorkspaceId",
        '--format', '{{.ID}}'
    )
    Write-CommandLog $dockerArguments
    $result = & docker @dockerArguments
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
    Write-CommandLog $arguments
    & docker @arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker image build failed with exit code $LASTEXITCODE." }
}

function Assert-AgentImage {
    Write-CommandLog @('image', 'inspect', $script:Image)
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
    Write-CommandLog $DockerArguments
    & docker @DockerArguments
    exit $LASTEXITCODE
}

function Remove-StaleSessionMarkers {
    param([string] $ContainerName)

    if (-not (Test-Path -LiteralPath $script:SessionsDir -PathType Container)) { return }
    $markers = Get-ChildItem -LiteralPath $script:SessionsDir -Filter "$ContainerName.*" -ErrorAction SilentlyContinue
    foreach ($marker in $markers) {
        $name = [string] $marker.Name
        $separator = $name.LastIndexOf('.')
        if ($separator -lt 0) { continue }
        $processId = 0
        if (-not [int]::TryParse($name.Substring($separator + 1), [ref] $processId)) { continue }
        if ($processId -eq $PID) { continue }
        if (-not (Get-Process -Id $processId -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $marker.FullName -Force
        }
    }
}

function Add-SessionMarker {
    param([string] $ContainerName)

    New-Item -ItemType Directory -Force -Path $script:SessionsDir | Out-Null
    Remove-StaleSessionMarkers $ContainerName
    New-Item -ItemType File -Force -Path (Join-Path $script:SessionsDir "$ContainerName.$PID") | Out-Null
}

function Confirm-ContainerDisposition {
    param([string] $Container)

    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        Write-Output "Keeping stopped agent container $Container"
        return
    }

    while ($true) {
        try {
            $response = Read-Host 'Keep or delete the stopped agent container? [K/d]'
        }
        catch {
            $response = 'keep'
        }

        if (-not $response -or $response -match '^(?i:k|keep)$') {
            Write-Output "Keeping stopped agent container $Container"
            return
        }
        if ($response -match '^(?i:d|delete)$') {
            Write-Output "Deleting agent container $Container"
            Write-CommandLog @('rm', $Container)
            & docker rm $Container | Out-Null
            if ($LASTEXITCODE -ne 0) {
                [Console]::Error.WriteLine("Unable to delete agent container $Container")
            }
            return
        }

        Write-Output "Please enter 'keep' or 'delete'."
    }
}

function Remove-SessionMarker {
    param([string] $ContainerName)

    Remove-Item -LiteralPath (Join-Path $script:SessionsDir "$ContainerName.$PID") -Force -ErrorAction SilentlyContinue
    Remove-StaleSessionMarkers $ContainerName
    $markers = @(Get-ChildItem -LiteralPath $script:SessionsDir -Filter "$ContainerName.*" -ErrorAction SilentlyContinue)
    if ($markers.Count -gt 0) { return }

    $running = Get-MatchingContainer
    if ($running) {
        Write-Output "Stopping agent container $running"
        Write-CommandLog @('stop', $running)
        & docker stop $running | Out-Null
        if ($LASTEXITCODE -ne 0) {
            [Console]::Error.WriteLine("Unable to stop agent container $running")
            return
        }
    }

    $container = Get-MatchingContainer -IncludeStopped
    if ($container) { Confirm-ContainerDisposition $container }
}

function Invoke-InteractiveDocker {
    param(
        [string] $ContainerName,
        [string[]] $DockerArguments
    )

    Add-SessionMarker $ContainerName
    Write-CommandLog $DockerArguments
    try {
        & docker @DockerArguments
        $exitCode = $LASTEXITCODE
    }
    finally {
        Remove-SessionMarker $ContainerName
    }
    exit $exitCode
}

try {
    $script:AgentHome = if ($env:AI_AGENT_HOME) {
        [System.IO.Path]::GetFullPath($env:AI_AGENT_HOME)
    } else {
        [System.IO.Path]::GetFullPath((Join-Path $HOME '.agent-container'))
    }
    $script:Image = if ($env:AI_AGENT_IMAGE) { $env:AI_AGENT_IMAGE } else { 'agent-container:latest' }
    $script:VerboseLogging = $env:AI_AGENT_VERBOSE -eq '1'
    $script:SshHostPort = $env:AI_AGENT_SSH_PORT
    $script:Workspace = (Get-Item -LiteralPath (Get-Location).Path).FullName
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($script:Workspace))
    $sha256.Dispose()
    $script:WorkspaceId = -join ($hashBytes | ForEach-Object { $_.ToString('x2') })
    $script:WorkspaceId = $script:WorkspaceId.Substring(0, 12)
    $workspaceName = [string](Split-Path -Leaf $script:Workspace)
    $workspaceName = $workspaceName.ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $workspaceName = $workspaceName.Trim('-')
    if ($workspaceName.Length -gt 50) { $workspaceName = $workspaceName.Substring(0, 50).TrimEnd('-') }
    if (-not $workspaceName) { $workspaceName = 'workspace' }
    $ContainerHostname = "$workspaceName-$($script:WorkspaceId)"
    $ContainerName = "agent-$ContainerHostname"
    $script:SessionsDir = Join-Path $script:AgentHome 'sessions'

    $ExtraPorts = [System.Collections.Generic.List[string]]::new()
    $ForwardPorts = [System.Collections.Generic.List[string]]::new()
    if ($env:AI_AGENT_FORWARD_PORT) { $ForwardPorts.Add($env:AI_AGENT_FORWARD_PORT) }
    $DockerRunArguments = [System.Collections.Generic.List[string]]::new()
    $Command = [System.Collections.Generic.List[string]]::new()
    $CredentialsDirectory = $null
    $CredentialsReadOnly = $false
    $CredentialsRequested = $false

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
            '^--forward-port$' {
                if (++$index -ge $Arguments.Count) { throw 'Missing value for --forward-port' }
                $ForwardPorts.Add($Arguments[$index]); continue
            }
            '^(-v|--verbose)$' { $script:VerboseLogging = $true; continue }
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

    foreach ($forwardPort in $ForwardPorts) {
        if ($forwardPort -notmatch '^(\d+)(?::(\d+))?$') {
            throw "Invalid --forward-port value: $forwardPort. Expected PORT or LOCAL:CONTAINER."
        }
        $localPort = [int] $Matches[1]
        $containerPort = if ($Matches[2]) { [int] $Matches[2] } else { $localPort }
        if ($localPort -lt 1 -or $localPort -gt 65535 -or
            $containerPort -lt 1 -or $containerPort -gt 65535) {
            throw "Invalid --forward-port value: $forwardPort. Ports must be between 1 and 65535."
        }
    }

    $builtIn = if ($Command.Count) { $Command[0] } else { '' }
    if ($builtIn -eq 'init') {
        if ($CredentialsRequested) {
            throw "Credential options cannot be used with 'agent init'; they only apply when creating a container."
        }

        $installDirectory = $PSScriptRoot.TrimEnd('\')
        $binDirectory = Join-Path $script:AgentHome 'bin'
        $null = New-Item -ItemType Directory -Force -Path $binDirectory

        $agentCmdShortcut = Join-Path $binDirectory 'agent.cmd'
        $agentPs1Shortcut = Join-Path $binDirectory 'agent.ps1'
        $agentContainerCmdShortcut = Join-Path $binDirectory 'agent-container.cmd'
        $agentContainerPs1Shortcut = Join-Path $binDirectory 'agent-container.ps1'

        $cmdBody = "@echo off`r`n`"%~dp0agent.ps1`" %*`r`nexit /b %ERRORLEVEL%"
        $ps1Body = "& `"$($installDirectory.Replace('\', '\\'))\\agent.ps1`" @args"

        Set-Content -LiteralPath $agentCmdShortcut -Value $cmdBody -NoNewline -Encoding ASCII
        Set-Content -LiteralPath $agentContainerCmdShortcut -Value $cmdBody -NoNewline -Encoding ASCII
        Set-Content -LiteralPath $agentPs1Shortcut -Value $ps1Body -NoNewline -Encoding ASCII
        Set-Content -LiteralPath $agentContainerPs1Shortcut -Value $ps1Body -NoNewline -Encoding ASCII

        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $pathEntries = @($userPath -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $alreadyPresent = $pathEntries | Where-Object { $_.TrimEnd('\') -ieq $binDirectory }

        if ($alreadyPresent) {
            Write-Output "PATH already contains $binDirectory."
        } else {
            $newPath = if ($userPath) { "$userPath;$binDirectory" } else { $binDirectory }
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
            Write-Output "Added $binDirectory to the user PATH."
        }

        Write-Output ''
        Write-Output 'Installed shortcuts:'
        Write-Output "  $agentCmdShortcut"
        Write-Output "  $agentContainerCmdShortcut"
        Write-Output ''
        Write-Output 'Open a new terminal window so the PATH change takes effect,'
        Write-Output 'then use agent or agent-container from anywhere.'
        exit 0
    }

    Assert-DockerAvailable

    if ($CredentialsRequested -and $builtIn -in @('build', 'exec', 'root', 'stop', 'delete', 'status', 'list', 'ls')) {
        throw "Credential options cannot be used with 'agent $builtIn'; they only apply when creating a container."
    }

    if ($builtIn -eq 'build') {
        $buildOptions = if ($Command.Count -gt 1) { $Command.GetRange(1, $Command.Count - 1).ToArray() } else { @() }
        Invoke-AgentBuild $buildOptions
        exit 0
    }

    if ($builtIn -eq 'tunnel') {
        if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
            throw 'OpenSSH Client is required. Install it from Windows Optional Features.'
        }
        $container = Get-RunningContainer
        $inspectArguments = @('inspect', '--format', '{{with index .NetworkSettings.Ports "22/tcp"}}{{(index . 0).HostPort}}{{end}}', $container)
        Write-CommandLog $inspectArguments
        $sshPort = & docker @inspectArguments
        $labelArguments = @('inspect', '--format', '{{index .Config.Labels "agent-forward-ports"}}', $container)
        Write-CommandLog $labelArguments
        $forwardPortLabel = & docker @labelArguments
        if (-not $sshPort -or -not $forwardPortLabel) {
            throw 'The running workspace container has no SSH forwards. Recreate it with: agent --forward-port PORT [command...]'
        }
        if (Get-Command ssh-keygen -ErrorAction SilentlyContinue) {
            & ssh-keygen -R "[localhost]:$sshPort" 2>$null | Out-Null
        }
        $sshArguments = @('-N', '-p', $sshPort)
        foreach ($port in $forwardPortLabel -split ',') {
            $parts = $port -split ':', 2
            if ($parts.Count -eq 1) { $sshArguments += @('-L', "${port}:localhost:${port}") }
            else { $sshArguments += @('-L', "$($parts[0]):localhost:$($parts[1])") }
        }
        $sshArguments += 'agent@localhost'
        & ssh @sshArguments
        exit $LASTEXITCODE
    }

    if ($builtIn -eq 'exec') {
        $container = Get-RunningContainer
        $execArguments = @('exec', '--interactive')
        $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
        if ($interactive) { $execArguments += '--tty' }
        $execArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $container)
        if ($Command.Count -eq 1) { $execArguments += 'bash' } else { $execArguments += $Command.GetRange(1, $Command.Count - 1) }
        if ($interactive -and $Command.Count -eq 1) {
            Invoke-InteractiveDocker $ContainerName $execArguments
        }
        Invoke-Docker $execArguments
    }

    if ($builtIn -eq 'root') {
        $container = Get-RunningContainer
        $execArguments = @('exec', '--interactive')
        $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
        if ($interactive) { $execArguments += '--tty' }
        $execArguments += @('--user', 'root', '--env', 'HOME=/root', '--workdir', '/workspace', $container)
        if ($Command.Count -eq 1) { $execArguments += 'bash' } else { $execArguments += $Command.GetRange(1, $Command.Count - 1) }
        if ($interactive -and $Command.Count -eq 1) {
            Invoke-InteractiveDocker $ContainerName $execArguments
        }
        Invoke-Docker $execArguments
    }

    if ($builtIn -eq 'stop') {
        $container = Get-MatchingContainer
        if (-not $container) { Write-Output "No running agent container for:`n  $script:Workspace"; exit 0 }
        Write-Output "Stopping agent container $container"
        Write-CommandLog @('stop', $container)
        & docker stop $container | Out-Null
        exit 0
    }

    if ($builtIn -eq 'delete') {
        $container = Get-MatchingContainer -IncludeStopped
        if (-not $container) { Write-Output "No agent container to delete for:`n  $script:Workspace"; exit 0 }
        Write-Output "Deleting agent container $container"
        Write-CommandLog @('rm', '-f', $container)
        & docker rm -f $container | Out-Null
        exit 0
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

    if ($builtIn -eq 'ralph') {
        $ralphContainer = Get-MatchingContainer
        if ($ralphContainer) {
            if ($CredentialsRequested) {
                throw 'Credential mounts require a new container. Run agent stop first.'
            }
            if ($ExtraPorts.Count -and -not (Test-RequestedPortsConfigured $ralphContainer $ExtraPorts)) {
                Throw-PortsRequireNewContainer
            }
            if ($ForwardPorts.Count -and -not (Test-RequestedForwardsConfigured $ralphContainer $ForwardPorts)) {
                Throw-ForwardsRequireNewContainer
            }
            $ralphArguments = @('exec', '--interactive')
            if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $ralphArguments += '--tty' }
            $ralphArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $ralphContainer)
            $ralphArguments += $Command
            Invoke-Docker $ralphArguments
        }
    }

    $runningContainer = Get-MatchingContainer
    if (-not $Command.Count -and $runningContainer) {
        if ($CredentialsRequested) { throw 'Credential mounts require a new container. Run agent stop first.' }
        if ($ExtraPorts.Count -and -not (Test-RequestedPortsConfigured $runningContainer $ExtraPorts)) {
            Throw-PortsRequireNewContainer
        }
        if ($ForwardPorts.Count -and -not (Test-RequestedForwardsConfigured $runningContainer $ForwardPorts)) {
            Throw-ForwardsRequireNewContainer
        }
        Write-Output "Attaching to agent container $runningContainer"
        $execArguments = @('exec', '--interactive')
        $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
        if ($interactive) { $execArguments += '--tty' }
        $execArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $runningContainer, 'bash')
        if ($interactive) {
            Invoke-InteractiveDocker $ContainerName $execArguments
        }
        Invoke-Docker $execArguments
    }

    if ($runningContainer) {
        if ($ExtraPorts.Count -and -not (Test-RequestedPortsConfigured $runningContainer $ExtraPorts)) {
            Throw-PortsRequireNewContainer
        }
        if ($ForwardPorts.Count -and -not (Test-RequestedForwardsConfigured $runningContainer $ForwardPorts)) {
            Throw-ForwardsRequireNewContainer
        }
        throw "An agent container is already running for this workspace:`n  $script:Workspace`n`nContainer:`n  $runningContainer`n`nUse one of:`n  agent`n  agent exec <command>`n  agent root [command]`n  agent stop`n  agent delete"
    }

    Assert-AgentImage

    $CredentialMountArguments = [System.Collections.Generic.List[string]]::new()
    if ($CredentialsRequested) {
        if (-not (Test-Path -LiteralPath $CredentialsDirectory -PathType Container)) {
            throw "Credential profile is not a directory: $CredentialsDirectory"
        }
        $CredentialsDirectory = (Get-Item -LiteralPath $CredentialsDirectory).FullName
        $credentialPaths = @(
            @{ Host = Join-Path $CredentialsDirectory '.ssh'; Container = '/home/agent/.ssh' },
            @{ Host = Join-Path $CredentialsDirectory '.config/gh'; Container = '/home/agent/.config/gh' }
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
            throw "Credential profile contains no supported credential directories:`n  $CredentialsDirectory`nExpected .ssh and/or .config/gh."
        }
    }

    $existingContainer = Get-MatchingContainer -IncludeStopped
    if ($existingContainer) {
        if ($CredentialsRequested) { throw 'Credential mounts require a new container. Run agent delete first.' }
        if ($ExtraPorts.Count -and -not (Test-RequestedPortsConfigured $existingContainer $ExtraPorts)) {
            Throw-PortsRequireNewContainer
        }
        if ($ForwardPorts.Count -and -not (Test-RequestedForwardsConfigured $existingContainer $ForwardPorts)) {
            Throw-ForwardsRequireNewContainer
        }
        Write-Output "Starting existing container $existingContainer..."
        Write-CommandLog @('start', $existingContainer)
        & docker start $existingContainer | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Unable to start container $existingContainer." }
        Write-PublishedPorts $existingContainer

        if ($builtIn -eq 'ralph') {
            Write-Output 'Starting Ralph in existing container...'
            $ralphArguments = @('exec', '--interactive')
            $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
            if ($interactive) { $ralphArguments += '--tty' }
            $ralphArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $existingContainer)
            $ralphArguments += $Command
            Invoke-InteractiveDocker $ContainerName $ralphArguments
        }

        Write-Output 'Attaching to existing container...'
        $execArguments = @('exec', '--interactive')
        $interactive = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
        if ($interactive) { $execArguments += '--tty' }
        $execArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $existingContainer, 'bash')
        if ($interactive) {
            Invoke-InteractiveDocker $ContainerName $execArguments
        }
        Invoke-Docker $execArguments
    }

    $PublishSsh = $false
    if ($Command.Count -and $Command[0] -eq 'codex') {
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
    }

    if ($ForwardPorts.Count) { $PublishSsh = $true }

    if (-not $ExtraPorts.Count -and -not $PublishSsh -and $builtIn -ne 'ralph') {
        Confirm-NoPublishedPorts
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
    @('run', '--interactive') | ForEach-Object { $runArguments.Add($_) }
    if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $runArguments.Add('--tty') }
    @(
        '--init', '--name', $ContainerName, '--hostname', $ContainerHostname,
        '--label', 'agent-container=true',
        '--label', "agent-workspace=$($script:WorkspaceId)",
        '--label', "agent-workspace-path=$($script:Workspace)",
        '--add-host', 'host.docker.internal:host-gateway',
        '--workdir', '/workspace',
        # Claude Code refuses --dangerously-skip-permissions as root unless it
        # is told the surrounding environment is already a sandbox.
        '--env', 'IS_SANDBOX=1',
        '--volume', "$($script:Workspace):/workspace",
        '--volume', "$(Join-Path $script:AgentHome '.codex'):/home/agent/.codex",
        # Codex app-server creates a Unix-domain control socket here. Keep it
        # out of the host-backed Codex state mount to avoid host filesystem
        # event forwarding for a live socket.
        '--tmpfs', '/home/agent/.codex/app-server-control:rw,nosuid,nodev,noexec',
        '--volume', "$(Join-Path $script:AgentHome '.claude'):/home/agent/.claude",
        '--volume', "$(Join-Path $script:AgentHome '.config/opencode'):/home/agent/.config/opencode",
        '--volume', "$(Join-Path $script:AgentHome '.local/share/opencode'):/home/agent/.local/share/opencode"
    ) | ForEach-Object { $runArguments.Add($_) }

    # Git for Windows may check symlinks out as files containing only their
    # target. Overlay the image instruction source in that case without
    # changing the host checkout. Linux containers use the tracked symlinks to
    # the canonical file installed in the image.
    $canonicalInstructions = Join-Path $script:AgentHome 'AGENTS-CONTAINER.md'
    $codexInstructions = Join-Path $script:AgentHome '.codex/AGENTS.md'
    $claudeInstructions = Join-Path $script:AgentHome '.claude/CLAUDE.md'
    $openCodeInstructions = Join-Path $script:AgentHome '.config/opencode/AGENTS.md'
    if ((Test-Path -LiteralPath $canonicalInstructions -PathType Leaf) -and
        (Test-GitSymlinkPlaceholder $codexInstructions '/usr/local/share/agent-container/AGENTS.md')) {
        @('--volume', "${canonicalInstructions}:/home/agent/.codex/AGENTS.md:ro") |
            ForEach-Object { $runArguments.Add($_) }
    }
    if ((Test-Path -LiteralPath $canonicalInstructions -PathType Leaf) -and
        (Test-GitSymlinkPlaceholder $claudeInstructions '/usr/local/share/agent-container/AGENTS.md')) {
        @('--volume', "${canonicalInstructions}:/home/agent/.claude/CLAUDE.md:ro") |
            ForEach-Object { $runArguments.Add($_) }
    }
    if ((Test-Path -LiteralPath $canonicalInstructions -PathType Leaf) -and
        (Test-GitSymlinkPlaceholder $openCodeInstructions '/usr/local/share/agent-container/AGENTS.md')) {
        @('--volume', "${canonicalInstructions}:/home/agent/.config/opencode/AGENTS.md:ro") |
            ForEach-Object { $runArguments.Add($_) }
    }

    $CredentialMountArguments | ForEach-Object { $runArguments.Add($_) }
    if ($ForwardPorts.Count) {
        $forwardPortLabel = $ForwardPorts -join ','
        @(
            '--label', "agent-forward-ports=$forwardPortLabel",
            '--env', 'AGENT_SSH_ENABLED=1',
            '--env', "AGENT_FORWARD_PORTS=$forwardPortLabel"
        ) | ForEach-Object { $runArguments.Add($_) }
    }

    Write-VerboseNote "workspace:      $script:Workspace"
    Write-VerboseNote "workspace id:   $script:WorkspaceId"
    Write-VerboseNote "container name: $ContainerName"
    Write-VerboseNote "hostname:       $ContainerHostname"
    Write-VerboseNote "image:          $script:Image"
    Write-VerboseNote "requested ports: $(if ($ExtraPorts.Count) { $ExtraPorts -join ' ' } else { 'none' })"

    Write-Output 'Published ports:'
    $publishedPortCount = 0
    if ($PublishSsh) {
        $resolvedSshPort = Get-SshPort
        @('--publish', "127.0.0.1:${resolvedSshPort}:22") | ForEach-Object { $runArguments.Add($_) }
        @('--env', "AGENT_SSH_HOST_PORT=$resolvedSshPort") | ForEach-Object { $runArguments.Add($_) }
        Write-Output "  SSH:   localhost:$resolvedSshPort -> container:22"
        $publishedPortCount++
    }
    foreach ($port in $ExtraPorts) {
        if ($port -notmatch ':') { $port = "${port}:${port}" }
        @('--publish', $port) | ForEach-Object { $runArguments.Add($_) }
        $containerPort = $port.Substring($port.LastIndexOf(':') + 1)
        $hostPort = $port.Substring(0, $port.LastIndexOf(':'))
        Write-Output "  Port:  $hostPort -> container:$containerPort"
        $publishedPortCount++
    }
    if (-not $publishedPortCount) { Write-Output '  (none)' }
    $DockerRunArguments | ForEach-Object { $runArguments.Add($_) }

    if ($builtIn -eq 'ralph') {
        $runArguments.Add('--detach')
        $runArguments.Add($script:Image)
        $runArguments.Add('sleep')
        $runArguments.Add('infinity')

        Add-SessionMarker $ContainerName
        $exitCode = 1
        try {
            Write-CommandLog $runArguments.ToArray()
            & docker @($runArguments.ToArray()) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Unable to start Ralph container; Docker exited with code $LASTEXITCODE."
            }

            $ralphArguments = @('exec', '--interactive')
            if (-not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected) { $ralphArguments += '--tty' }
            $ralphArguments += @('--user', 'agent', '--env', 'HOME=/home/agent', '--workdir', '/workspace', $ContainerName)
            $ralphArguments += $Command
            Write-CommandLog $ralphArguments
            & docker @ralphArguments
            $exitCode = $LASTEXITCODE
        }
        finally {
            Remove-SessionMarker $ContainerName
        }
        exit $exitCode
    }

    $runArguments.Add($script:Image)
    $Command | ForEach-Object { $runArguments.Add($_) }
    Invoke-InteractiveDocker $ContainerName $runArguments.ToArray()
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
