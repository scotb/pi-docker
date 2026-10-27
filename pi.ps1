# pi.ps1 — Windows-side twin of pi.sh.
#
# The project directory is the current location. Launching from
# C:\Users\scot\foo mounts it at /host/C/Users/scot/foo inside the container.
#
# Why /host/<drive>/<path> rather than mirroring the Windows path exactly?
# Same reasons as pi.sh: every mount stays inside one subtree, so a project
# can never shadow the container's own files (/usr/lib/node_modules,
# /home/ubuntu/.pi, /etc). The drive letter becomes the first path component
# (C: -> C).
#
# What this does NOT do, and why:
#   * Projects on the WSL side (/data, ext4 inside the WSL2 VM) cannot be
#     launched from Windows at all — the Windows docker CLI can only
#     bind-mount Windows paths.
#   * --dev is refused: the live fork repos sit on the WSL side next to
#     /data, invisible from Windows. Use pi.sh from WSL for --dev.
#   * UNC paths (\\server\share) are refused: not bind-mountable by the
#     Windows docker CLI.
#   * 8.3 short names and junctions are not resolved. Two routes to the same
#     directory count as two projects, with separate history (same accepted
#     limitation as symlinks in pi.sh).
#
# Shared with pi.sh, because both sides talk to the same Docker daemon:
# the pi-state named volume, the pi-sandbox image, and LLAMA_SERVER_URL
# (host.docker.internal resolves the same from a Windows-launched container).
#
# Install: copy this file to a Windows drive (e.g. C:\Users\<you>\bin\pi.ps1)
# and add that folder to PATH. One-time: Set-ExecutionPolicy -Scope
# CurrentUser RemoteSigned.

param(
    [switch]$Dev,
    [string]$Tag = 'latest',
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PiArgs
)

$project = (Get-Location).Path.TrimEnd('\')

if ($project -match '^[A-Za-z]:$') {
    [Console]::Error.WriteLine("pi: refusing to launch from '$project'.")
    [Console]::Error.WriteLine("    Everything below it would be mounted into the container, which")
    [Console]::Error.WriteLine("    defeats the isolation this sandbox exists to provide.")
    [Console]::Error.WriteLine("    cd into a project directory and try again.")
    exit 1
}

if ($project -ieq $HOME.TrimEnd('\')) {
    [Console]::Error.WriteLine("pi: refusing to launch from '$project'.")
    [Console]::Error.WriteLine("    Everything below it would be mounted into the container, which")
    [Console]::Error.WriteLine("    defeats the isolation this sandbox exists to provide.")
    [Console]::Error.WriteLine("    cd into a project directory and try again.")
    exit 1
}

if ($project -match '^\\\\') {
    [Console]::Error.WriteLine("pi: refusing to launch from '$project'.")
    [Console]::Error.WriteLine("    UNC paths (\\server\share) cannot be bind-mounted by the")
    [Console]::Error.WriteLine("    Windows docker CLI. Use a local drive path.")
    exit 1
}

if ($Dev) {
    [Console]::Error.WriteLine("pi: --dev is not supported from Windows.")
    [Console]::Error.WriteLine("    The live fork repos (pi-subagents, self-compact-pi-agent)")
    [Console]::Error.WriteLine("    live on the WSL side (/data/apps, ext4), which the Windows")
    [Console]::Error.WriteLine("    docker CLI cannot bind-mount. Use pi.sh from WSL for --dev.")
    exit 1
}

# Bare tag gets the pi-sandbox: prefix; a tag containing ':' is used verbatim.
if ($Tag -notmatch ':') { $Tag = "pi-sandbox:$Tag" }

# C:\foo -> /host/C/foo: the drive letter keeps its name but loses its
# colon, so the -v spec never carries a colon in its target half.
$containerPath = "/host/" + $project.Substring(0, 1) + '/' + $project.Substring(3).Replace('\', '/')
$volume = 'pi-state'
if ($env:PI_VOLUME) { $volume = $env:PI_VOLUME }

$dockerArgs = @(
    'run', '-it', '--rm',
    '-v', "${volume}:/home/ubuntu/.pi",
    '-v', "${project}:${containerPath}",
    '-e', 'LLAMA_SERVER_URL=http://host.docker.internal:8007',
    '-w', $containerPath,
    $Tag
)
if ($PiArgs.Count -gt 0) { $dockerArgs += $PiArgs }

& docker @dockerArgs
exit $LASTEXITCODE
