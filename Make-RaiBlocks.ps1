If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    Write-Error "** RUN SCRIPT AS ADMINISTRATOR **"
    Return
}

if (-NOT (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio")) {
    Write-Error "** Visual Studio 2012 or newer is required. You need to customize script if not using 2017. **"
    Return
}

clear

$rootPath = "$env:USERPROFILE\projects\raiblocks"  # change this to development path
$githubRepo = "https://github.com/clemahieu/raiblocks.git"
$python2path = 'C:\Python27'
$qtRelease = "5.10"
$vsVersion = "2017"
$boostVersion = "1.63.0"

$boostBaseName = "boost_" + $boostVersion.Replace(".","_")
$qtReleaseFull = "$qtRelease.0"
$downloadPath = "$rootpath\downloads"
$repoPath = "$rootPath\github"
$buildPath = "$rootPath\github-build"

$downloads = $(
    @{name="WGET";
        url="https://eternallybored.org/misc/wget/releases/wget-1.19.2-win64.zip";
        filename="wget-1.19.2-win64.zip";
        extractPath="$($env:TEMP)\wget"},
    @{name="NSIS";
        url="https://downloads.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1-setup.exe";
        filename="nsis-3.02.1-setup.exe";
        extractPath="$buildPath\nsis";
        installPath="$((Get-Item "Env:ProgramFiles(x86)").Value)\NSIS\";
        addPath="$((Get-Item "Env:ProgramFiles(x86)").Value)\NSIS\bin"},
    @{name="Boost";
        url="https://dl.bintray.com/boostorg/release/$boostVersion/source/$boostBaseName.zip";
        filename="$boostBaseName.zip";
        extractPath="$buildPath\boost-src"},
    @{name="Qt";
        url="http://download.qt.io/official_releases/qt/$qtRelease/$qtReleaseFull/qt-opensource-windows-x86-$qtReleaseFull.exe";
        filename="qt-opensource-windows-x86-$qtReleaseFull.exe";
        installPath="C:\Qt\Qt$qtReleaseFull";
        addPath="C:\qt\Qt$qtReleaseFull\$qtReleaseFull\msvc$vsVersion`_64\bin;C:\Qt\Qt$qtReleaseFull\Tools\QtCreator\bin";
        installComment="Please check msvc$vsVersion 64-bit prebuilt components";
        linkedInstallName="qt";
        linkedInstallPath="$qtReleaseFull\msvc$vsVersion`_64";
    },
    #@{name="Qt-src";
    #    url="http://download.qt.io/official_releases/qt/$qtRelease/$qtReleaseFull/single/qt-everywhere-src-$qtReleaseFull.zip";
    #    filename="qt-everywhere-src-$qtReleaseFull.zip";
    #    extractPath="$buildPath\qt-src"},
    @{name="Python2";
        url="https://www.python.org/ftp/python/2.7.14/python-2.7.14.amd64.msi";
        filename="python-2.7.14.amd64.msi";
        extractPath="$($env:TEMP)\python2";
        installPath="$python2path";
        addPath="$python2path"}
)

##############################################################################

Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)
    if (!(Test-Path $outpath)) {
        md -Force $outpath | out-null
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
}

function Set-VsCmd
{
    param(
        [parameter(Mandatory=$true, HelpMessage="Enter VS version as 2012, 2013, 2015, 2017")]
        [ValidateSet(2012,2013,2015,2017)]
        [int]$version
    )
    $VS_VERSION = @{ 2012 = "11.0"; 2013 = "12.0"; 2015 = "14.0"; 2017 = "" }
    if ($version -eq 2017)
    {
        $env:vsVersion = "15.0"
        $env:msvcver="msvc-14.1"
        Push-Location
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio\2017"
        Set-Location $targetDir
        $vcvars = Get-ChildItem -Recurse VsDevCmd.bat | Resolve-Path -Relative
        $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'})\bin"
        $env:VS_ARCH = "Visual Studio 15 2017"
        Pop-Location
    }
    elseif ($version -eq 2015)
    {
        $path = "C:\Program Files (x86)\Microsoft Visual Studio $($VS_VERSION[$version])"
        $env:vsVersion = $VS_VERSION[$version]
        $env:msvcver="msvc-14.0"
        Push-Location
        $targetDir = "$path\Common7\Tools"
        Set-Location $targetDir
        $vcvars = "vcvarsall.bat"
        $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'} | Resolve-Path -Relative)\bin"
        $env:VS_ARCH = "Visual Studio 14 2015"
        Pop-Location
    }
    else
    {
        if ($VS_VERSION -eq 2013) {
            $env:msvcver="msvc-12.0"
            $env:VS_ARCH = "Visual Studio 12 2013"
        } else {
            $env:msvcver="msvc-11.0"
            $env:VS_ARCH = "Visual Studio 11 2012"
        }

        $env:vsVersion = $VS_VERSION[$version]
        Push-Location
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio $($VS_VERSION[$version])\VC"
        Set-Location $targetDir
        $vcvars = "vcvarsall.bat"
        $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'} | Resolve-Path -Relative)\bin"
        Pop-Location
    }
  
    if (!(Test-Path (Join-Path $targetDir $vcvars))) {
        "* Error: Visual Studio $version not installed"
        return
    }
    Write-host "* Running $targetDir $vcvars"
    Push-Location $targetDir
    cmd /c $vcvars + "&set" |
    ForEach-Object {
      if ($_ -match "(.*?)=(.*)") {
        #Write-Host "* SET Env: $($matches[1])`" = `"$($matches[2])`""
        Set-Item -force -path "ENV:\$($matches[1])" -value "$($matches[2])"
      }
    }
    Pop-Location
    write-host "`nVisual Studio $version Command Prompt variables set." -ForegroundColor Yellow
}

function Resolve-Anypath
{
    param ($file)
    $paths = (".;" + $env:PATH).Split(";")
    foreach ($path in $paths) {
        $testPath = Join-Path $path $file
        if (Test-Path $testPath) {
            return ($testPath)
        }
    }
    return $false
}

function Invoke-SearchReplace {
    [CmdletBinding()]    
    param(
        [string] $file,
        [string] $searchFor,
        [string] $replaceWith
    )
    $DebugPreference = "Continue"
    if ((Get-Item $file).length -eq 0) {
        return
    } 
    $content = Get-Content $file -Raw
    $saveContent = $content
    $searchFor = "(?smi)$searchFor"
    $regex = [Regex]::new($searchFor)
    $match = $regex.Matches($content)
    if ($match.Success -eq $TRUE) {
        $content = $content -replace $searchFor, $replaceWith
        $content | Out-File $file -Encoding ascii
    }
}

function exec
{
    # fixes bad applications that output to STDERR instead of STDOUT
    param
    (
        [ScriptBlock] $ScriptBlock,
        [string] $StderrPrefix = "",
        [int[]] $AllowedExitCodes = @(0)
    )
    $backupErrorActionPreference = $script:ErrorActionPreference

    $script:ErrorActionPreference = "Continue"
    try
    {
        & $ScriptBlock 2>&1 | ForEach-Object -Process `
            {
                if ($_ -is [System.Management.Automation.ErrorRecord])
                {
                    "$StderrPrefix$_"
                }
                else
                {
                    "$_"
                }
            }
        if ($AllowedExitCodes -notcontains $LASTEXITCODE)
        {
            Write-Error "* Execution failed with exit code $LASTEXITCODE"
            return $LASTEXITCODE
        }
    }
    finally
    {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}

function Pack-EnvPath {
    return
    $latestTs = dir "C:\Program Files (x86)\Microsoft SDKs\TypeScript\" | Sort | Select -last 1 $($_.Name)
    $fso = New-Object -ComObject "Scripting.FileSystemObject"
    $shortpaths = @();
    $originalPaths = [environment]::GetEnvironmentVariable("path", "Machine").Split(";")
    foreach ($path in $originalPaths) {
        $fpath = [System.IO.Path]::GetFullPath("$path");
        if ($fpath.StartsWith('C:\Program Files (x86)\Microsoft SDKs\TypeScript\')) {
            $fpath = "C:\Program Files (x86)\Microsoft SDKs\TypeScript\$latestTs\";
        }
        $fspath = $fso.GetFolder("$fpath").ShortPath;
        $foundIdx = $shortpaths.IndexOf($fspath);
        if ($foundIdx -gt -1) {	continue; }
        write-host $fpath  -->  $fspath;
        $shortpaths += $fspath;
    }
    $env:Path = $($shortpaths -join ";");
}

function Add-EnvPath {
    param
    (
        [string] $Item = "",
        [bool] $Append = $true
    )
    Pack-EnvPath
    if ($Append -eq $true) {
        $env:PATH="$env:PATH;$Item"
    }
    else {
        $env:PATH="$Item;$env:PATH"
    }
    Pack-EnvPath    
}


##############################################################################

Write-Host "* Building RaiBlocks..."

if (!(Test-Path $rootPath)){
    mkdir $rootPath | out-null
}

if (!(Test-Path $repoPath)){
    Write-Host "* Cloning $githubRepo into $repoPath"
    & git clone -q $githubRepo $repoPath
}

if (!(Test-Path $buildPath)){
    #Write-Host "* Creating working repo into $buildPath"
    #mkdir $buildPath | out-null
    Write-Host "* Creating working repo from $repoPath into $buildPath"
    copy -Recurse $repoPath $buildPath | out-null
}
cd $buildPath

foreach ($file in $downloads){
    $name = "$($file.name)"
    $filePath = "$downloadPath\$($file.filename)"
    $url = "$($file.url)"
    $extractPath = "$($file.extractPath)"
    $installPath = "$($file.installPath)"
    $linkedInstallName = "$($file.linkedInstallName)"
    $linkedInstallPath = "$($file.linkedInstallPath)"
    $installComment = "$($file.installComment)"
    $addPath = "$($file.addPath)"
    $wget = "$env:TEMP\wget.exe"
    Write-Host "* Checking $name"
    if ($file.deleteBeforeDownload -eq $true -and (Test-Path $filePath)) {
        Write-Host "*   Deleting old download $filePath"
        del -Force -Recurse $filePath
    }
    if ($file.deleteBeforeExtract -eq $true -and (Test-Path $extractPath)) {
        Write-Host "*   Deleting old extraction $extractPath"
        del -Force -Recurse $extractPath
    }

    if (!(Test-Path $filePath)) {
        Write-Host "*   Missing $filePath, downloading $url"
        if (Test-Path $wget) {
            Push-Location
            cd $filePath\..
            exec { & $wget --no-verbose --continue $url }
            Pop-Location
        }
        else {
            Invoke-WebRequest -Uri $url -OutFile $filePath
        }
    }
    if (($filePath -match ".msi") -or ($filePath -match ".exe")) {
        if ($installPath -ne "" -and !(Test-Path "$installPath")) {
            Write-Host "*   Installing $filepath."
            if ($installComment -ne "") {
                Write-Host "*** $installComment ***"
            }
            & $filePath | out-string
        }
    }
    if (($filePath -match ".zip") -and (!(Test-Path $extractPath))) {
        Write-Host "*   Unzipping $filePath into $extractPath..."
        Push-Location
        Unzip $filePath $extractPath
        cd $extractPath
        if ((Get-ChildItem | ?{ $_.PSIsContainer }).Length -eq 1) {
            cd *
        }
        move -force * ..
        Pop-Location
    }
    if (($linkedInstallName -ne "") -and (Test-Path "$installPath\$linkedInstallPath") -and (!(Test-Path "$buildPath\$linkedInstallName"))) {
        Write-Host "*   Creating symbolic link from $buildPath\$linkedInstallName to $installPath\$linkedInstallPath"
        Push-Location
        cd $buildPath
        New-Item -ItemType SymbolicLink -Name $linkedInstallName -Target $installPath\$linkedInstallPath | out-null
        Pop-Location
    }
    if (($addPath -ne "") -and (!($env:PATH.Contains($addPath)))) {
        Write-Host "*   Adding to PATH $addPath"
        Add-EnvPath -Item $addPath
    }
}
#Write-Host "** Please verify build tools are installed before continuing **"
#pause

# add python to path
if ($env:PYTHONPATH -eq $null) {
    Write-Host "*   Set PYTHONPATH=$python2path"
    $env:PYTHONPATH = $python2path
}

## setup Visual Studio path
Set-VsCmd -version $vsVersion

# add cmake to path
if (!($env:PATH.Contains($env:CMAKE_BIN))) {
    Write-Host "*   Adding to PATH $env:CMAKE_BIN"
    Add-EnvPath -Item $env:CMAKE_BIN
}

## Make BOOST
cd $buildPath\boost-src
if (!(Test-Path "project-config.jam")) {
    Write-Host "* Defining BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE in boost\config\user.hpp"
    Invoke-SearchReplace "$buildPath\boost-src\boost\config\user.hpp" "// define this to locate a compiler config file:" "`n#define BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE`n// define this to locate a compiler config file:"
    & ./bootstrap.bat
}

$buildBoostPath = "$buildPath\boost"
$buildBoostBuildPath = "$buildPath\boost-build"
$buildBoostSrcPath = "$buildPath\boost-src"
$buildBoostProjectConfig = "$buildBoostSrcPath\project-config.jam"
$buildQtPath = "$buildPath\qt"
$buildQtSrcPath = "$buildPath\qt-src"

$env:BOOST_ROOT="$buildBoostSrcPath"
$env:BOOST_INCLUDE="$buildBoostPath\include"
$env:BOOST_LIBDIR= "$buildBoostPath\lib"
$env:Qt5_DIR="$buildQtPath"
$env:RAIBLOCKS_GUI="ON"
$env:ENABLE_AVX2="ON"
$env:CRYPTOPP_CUSTOM="ON"

If (!(Get-Content $buildBoostProjectConfig | Select-String -Pattern "cl.exe")) {
    Write-Host "* Fixing $buildBoostProjectConfig"
    $clPath = Resolve-Anypath cl.exe
    Write-Host "* Patching project-config.jam with $clPath"
    Invoke-SearchReplace $buildBoostProjectConfig "using msvc ;" "`nusing msvc : $env:vsVersion : `"$clPath`";"
}
if (!(Test-Path "$buildBoostBuildPath\boost")) {
    & ./b2 --prefix=$buildBoostPath --build-dir=$buildBoostBuildPath link=static address-model=64 install
}

## Make Qt source when available
if (Test-Path $buildQtSrcPath) {
    cd $buildQtSrcPath 
    if (!(Test-Path $buildQtPath)) {
        & ./configure -shared -opensource -nomake examples -nomake tests -confirm-license -prefix $env:Qt5_DIR
    }
    & nmake -D BOOST_ROOT="$env:BOOST_ROOT" -D Qt5_DIR="$env:Qt5_DIR" -D RAIBLOCKS_GUI=ON -D ENABLE_AVX2=ON -D CRYPTOPP_CUSTOM=ON
    & nmake install
}
cd $buildPath
exec { & git submodule update --init --recursive }
#cmake -D BOOST_ROOT="$env:BOOST_ROOT" -D Qt5_DIR="$env:Qt5_DIR" -DRAIBLOCKS_GUI=ON -DENABLE_AVX2=ON -DCRYPTOPP_CUSTOM=ON -G $env:VS_ARCH
cmake -G $env:VS_ARCH