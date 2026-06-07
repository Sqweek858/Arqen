param(
    [string]$RepoRoot = ""
)

$ErrorActionPreference = "Stop"
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
    $RepoRoot = (git rev-parse --show-toplevel).Trim()
}

$failed = $false
function Emit-Check {
    param([string]$Name, [bool]$Ok, [string]$Message)
    if ($Ok) { Write-Host "PASS|$Name|$Message" } else { Write-Host "FAIL|$Name|$Message"; $script:failed = $true }
}

$compiler = Join-Path $RepoRoot "Tools/arqc_m10g.exe"
$tempDir = Join-Path $RepoRoot "Build/Temp/strict_ir"
$errorDir = Join-Path $RepoRoot "Build/Errors"
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
New-Item -ItemType Directory -Force -Path $errorDir | Out-Null

Emit-Check "strict_ir_compiler_present" (Test-Path $compiler) "arqc_m10g.exe available"

function Write-IrCase {
    param([string]$Name, [string]$Body)
    $path = Join-Path $tempDir ($Name + ".arqir")
    [System.IO.File]::WriteAllText($path, ($Body.Trim() + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    return $path
}

function Invoke-BackendOnly {
    param([string]$IrPath, [string]$OutName)
    $outPath = Join-Path $tempDir ($OutName + ".exe")
    Push-Location $RepoRoot
    try {
        & $compiler --backend-only $IrPath -o $outPath *> $null
        $exit = $LASTEXITCODE
        if ($null -eq $exit) { $exit = if ($?) { 0 } else { 1 } }
        return [int]$exit
    } finally {
        Pop-Location
    }
}

$valid = Write-IrCase "valid_show_message" @'
ARQIR|version=0
TARGET|kind=program|name=StrictIrValid
META|source=strict_ir_valid.arq
CONST|id=str_0|type=text|value=StrictIr
CONST|id=str_1|type=text|value=Hello
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=show_message|title=str_0|text=str_1
ACTION|id=act_1|op=exit|code=i32_0
ENTRY|actions=act_0,act_1
END
'@

$cases = @(
    @{ Name = "strict_ir_valid_show_message"; Path = $valid; WantExit = 0; Detail = "valid backend-only IR accepted" },
    @{ Name = "strict_ir_duplicate_action"; WantExit = 1; Detail = "duplicate ACTION rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=DupAction
META|source=dup.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=exit|code=i32_0
ACTION|id=act_0|op=exit|code=i32_0
ENTRY|actions=act_0
END
'@ },
    @{ Name = "strict_ir_duplicate_const"; WantExit = 1; Detail = "duplicate CONST rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=DupConst
META|source=dupconst.arq
CONST|id=i32_0|type=int|value=0
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=exit|code=i32_0
ENTRY|actions=act_0
END
'@ },
    @{ Name = "strict_ir_missing_entry"; WantExit = 1; Detail = "missing ENTRY rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=NoEntry
META|source=noentry.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=exit|code=i32_0
END
'@ },
    @{ Name = "strict_ir_missing_action_reference"; WantExit = 1; Detail = "ENTRY missing action rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=MissingRef
META|source=missingref.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=exit|code=i32_0
ENTRY|actions=act_0,act_404
END
'@ },
    @{ Name = "strict_ir_unknown_line"; WantExit = 1; Detail = "unknown IR line rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=UnknownLine
META|source=unknown.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=exit|code=i32_0
POTATO|value=nope
ENTRY|actions=act_0
END
'@ },
    @{ Name = "strict_ir_action_missing_op"; WantExit = 1; Detail = "ACTION without op rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=MissingOp
META|source=missingop.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|code=i32_0
ENTRY|actions=act_0
END
'@ },
    @{ Name = "strict_ir_unsupported_dx12"; WantExit = 1; Detail = "unsupported DX12 action rejected"; Body = @'
ARQIR|version=0
TARGET|kind=program|name=Dx12Rejected
META|source=dx12.arq
CONST|id=i32_0|type=int|value=0
ACTION|id=act_0|op=dx12
ACTION|id=act_1|op=exit|code=i32_0
ENTRY|actions=act_0,act_1
END
'@ }
)

foreach ($case in $cases) {
    $casePath = if ($case.ContainsKey("Path")) { $case["Path"] } else { Write-IrCase $case["Name"] $case["Body"] }
    if (-not (Test-Path $compiler)) {
        Emit-Check $case["Name"] $false "compiler missing"
        continue
    }
    $exit = Invoke-BackendOnly $casePath $case["Name"]
    Emit-Check $case["Name"] ($exit -eq $case["WantExit"]) ("$($case["Detail"]) exit=$exit expected=$($case["WantExit"])" )
}

if ($failed) { exit 1 }
exit 0
