function Build-Orc
{
    <#
    .SYNOPSIS
        Build wrapper around CMake to ease CI integration.

        Allows one-liners for building multiple configurations: x86, x64, Debug, MinSizeRel...

    .PARAMETER Source
        Path to DFIR-ORC source root directory to build.

    .PARAMETER BuildDirectory
        Output directory. Must be a subdirectory of Path. Relative path will be treated as relative to $Path.
        Default value: '$Source/build'.

    .PARAMETER Output
        Build artifacts output directory.

    .PARAMETER Architecture
        Target architecture (x86, x64).

    .PARAMETER Configuration
        Target configuration (Debug, MinSizeRel, Release, RelWithDebInfo).

    .PARAMETER Runtime
        Target runtime (static, dynamic). Default value: 'static'.

    .PARAMETER Vcpkg
        Override default directory for vcpkg.

    .PARAMETER ApacheOrc
        Build with ApacheOrc support.

    .PARAMETER Parquet
        Build with Parquet support.

    .PARAMETER SSDeep
        Build with SSDeep support.

    .PARAMETER Clean
        Clean build directory.

    .OUTPUTS
        None or error on failure.

    .EXAMPLE
        Build DFIR-Orc in 'F:\dfir-orc\build'.

        . F:\Orc\tools\ci\build.ps1
        Build-Orc -Source c:\dfir-orc\ -Architecture x86,x64 -Configuration Debug,MinSizeRel
    #>

    Param (
        [Parameter(Mandatory)]
        [System.IO.DirectoryInfo]
        $Source,
        [Parameter()]
        [System.IO.DirectoryInfo]
        $BuildDirectory = (Join-Path "${Source}" "build"),
        [Parameter()]
        [System.IO.DirectoryInfo]
        $Output,
        [Parameter(Mandatory)]
        [ValidateSet('x86', 'x64', IgnoreCase=$false)]
        [String[]]
        $Architecture,
        [Parameter()]
        [ValidateSet('vs2017', 'vs2019', 'vs2022')]
        [String]
        $ToolChain = 'vs2019',
        [Parameter()]
        [ValidateSet('v141', 'v141_xp', 'v142', 'v143')]
        [String]
        $PlatformToolSet = "v141",
        [Parameter()]
        [String]
        $SystemVersion,
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'MinSizeRel', 'RelWithDebInfo', IgnoreCase=$false)]
        [String[]]
        $Configuration,
        [Parameter()]
        [ValidateSet('static', 'dynamic', IgnoreCase=$false)]
        [String]
        $Runtime = 'static',
        [Parameter()]
        [System.IO.DirectoryInfo]
        $Vcpkg,
        [Parameter()]
        [switch]
        $ApacheOrc,
        [Parameter()]
        [switch]
        $Parquet,
        [Parameter()]
        [switch]
        $SSDeep,
        [Parameter()]
        [switch]
        $Clean
    )

    $OrcPath = (Resolve-Path -Path $Source).Path.trim("\")

    if(-not $Vcpkg) {
        $Vcpkg = "${OrcPath}\external\vcpkg"
    }
    $Vcpkg = (Resolve-Path -Path $Vcpkg).Path.trim("\")

    if(-not [System.IO.Path]::IsPathRooted($BuildDirectory))
    {
        $BuildDirectory = Join-Path "${OrcPath}" "${BuildDirectory}"
    }

    if(-not [System.IO.Path]::IsPathRooted($Output))
    {
        $Output = Join-Path "$OrcPath" "${Output}"
    }

    $Generators = @{
        "vs2017_x86" = @("-G `"Visual Studio 15 2017`"")
        "vs2017_x64" = @("-G `"Visual Studio 15 2017 Win64`"")
        "vs2019_x86" = @(
                "-G `"Visual Studio 16 2019`""
                "-A Win32"
        )
        "vs2019_x64" = @(
                "-G `"Visual Studio 16 2019`""
                "-A x64"
        )
        "vs2022_x86" = @(
                "-G `"Visual Studio 17 2022`""
                "-A Win32"
        )
        "vs2022_x64" = @(
                "-G `"Visual Studio 17 2022`""
                "-A x64"
        )
    }

    $CMakeGenerationOptions = @(
        "-S `"${OrcPath}`""
        "-T ${PlatformToolSet}"
        "-DORC_BUILD_VCPKG=ON"
        "-DORC_VCPKG_ROOT=`"${Vcpkg}`""
        "-DCMAKE_TOOLCHAIN_FILE=`"${Vcpkg}\scripts\buildsystems\vcpkg.cmake`""
    )

    if($SystemVersion)
    {
        $CMakeGenerationOptions += "-DCMAKE_SYSTEM_VERSION=$SystemVersion"
    }

    if($ApacheOrc)
    {
        $CMakeGenerationOptions += "-DORC_BUILD_APACHE_ORC=ON"
    }

    if($Parquet)
    {
        $CMakeGenerationOptions += "-DORC_BUILD_PARQUET=ON"
    }

    if($SSDeep)
    {
        $CMakeGenerationOptions += "-DORC_BUILD_SSDEEP=ON"
    }

    $CMakeExe = Find-CMake
    if(-not $CMakeExe)
    {
        Write-Error "Cannot find 'cmake.exe'"
        return
    }
    else
    {
        Invoke-NativeCommand $CMakeExe --version
    }

    foreach($Arch in $Architecture)
    {
        $BuildDir = Join-Path "${BuildDirectory}" "${Arch}"
        if (Test-Path -PathType Container $BuildDir)
        {
            if($Clean)
            {
                Remove-Item -Force -Recurse -Path $BuildDir
            }

            New-Item -Force -ItemType Directory -Path $BuildDir | Out-Null
        }

        $Generator = $Generators[$ToolChain + "_" + $Arch]

        foreach($Config in $Configuration)
        {
            $Parameters = $Generator + $CMakeGenerationOptions + "-DVCPKG_TARGET_TRIPLET=${Arch}-windows-${Runtime}" + "-B `"${BuildDir}`""
            Invoke-NativeCommand $CMakeExe $Parameters
            Invoke-NativeCommand $CMakeExe "--build ${BuildDir} --config ${Config} -- -maxcpucount"
            Invoke-NativeCommand $CMakeExe "--install ${BuildDir} --prefix ${Output} --config ${Config}"
        }
    }
}

function Find-CMake
{
    $CMakeExe = Get-Command "cmake.exe" -ErrorAction SilentlyContinue
    if($CMakeExe)
    {
        return $CMakeExe
    }

    $Locations = @(
        "c:\Program Files\Microsoft Visual Studio\2022\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        "c:\Program Files (x86)\Microsoft Visual Studio\2019\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        "c:\Program Files (x86)\Microsoft Visual Studio\*\*\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
    )

    foreach($Location in $Locations)
    {
        $Path = Get-Item -Path $Location
        if($Path)
        {
            return $Path
        }
    }
}

#
# Invoke-NativeCommand
#
# Execute a native command and throw if its exit code is not 0.
#
# This simple wrapper could be smarter and rely on parameters splatting.
# In the case of CMake its not so easy to keep generic approach because of its handling of the cli options.
#
# In an attempt to use splatting I had those issues:
#
# - Options uses '-'
# - Options '-D' can have "-D<KEY>=<VALUE>" or "-D<KEY:TYPE>=<VALLUE>"
# - VALUE can be a bool or a path (quotes...)
# - Options like '-T <VALUE>' is followed by a space before <VALUE>
# ...
#
# cmake.exe -G "Visual Studio 16 2019" -A x64 -T v141_xp -DORC_BUILD_VCPKG=ON -DCMAKE_TOOLCHAIN_FILE="C:\dev\orc\dfir-orc\external\vcpkg\scripts\buildsystems\vcpkg.cmake" "C:\dev\orc\dfir-orc\"
#
function Invoke-NativeCommand()
{
    param(
        [Parameter(ValueFromPipeline=$true, Mandatory)]
        [string]
        $Command,
        [Parameter(ValueFromPipeline=$true, Mandatory)]
        [String[]]
        $Parameters
    )

    $Child = Start-Process -PassThru $Command -ArgumentList $Parameters -NoNewWindow

    # Workaround on 'Start-Process -Wait ...' which hangs sometimes (psh 7.0.3)
    $Child | Wait-Process

    if ($Child.ExitCode)
    {
        $ExitCode = [String]::Format("0x{0:X}", $Child.ExitCode)
        throw "'${Command} ${Parameters}' exited with code ${ExitCode}"
    }
}
