If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    Write-Error "** RUN SCRIPT AS ADMINISTRATOR **"
    Return
}

if (-NOT (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio")) {
    Write-Error "** Visual Studio 2012 or newer is required **"
    Return
}

clear

$rootPath = "$env:USERPROFILE\dev\raiblocks"  # change this to development path
$downloadPath = "$rootpath\downloads"
$repoPath = "$rootPath\github"
$buildPath = "$rootPath\github-build"
$githubRepo = "https://github.com/clemahieu/raiblocks.git"
$python2path = 'C:\Python27'

$downloads = $(

    @{name="WGET";
        url="https://eternallybored.org/misc/wget/releases/wget-1.19.2-win64.zip";
        filename="wget-1.19.2-win64.zip";
        extractPath="$($env:TEMP)\wget"},

    @{name="NSIS";
        url="https://downloads.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1-setup.exe";
        filename="nsis-3.02.1-setup.exe";
        extractPath="$buildPath\nsis";
        installPath="$((Get-Item "Env:ProgramFiles(x86)").Value)\NSIS\"},

    @{name="Boost";
        url="https://dl.bintray.com/boostorg/release/1.66.0/source/boost_1_66_0.zip";
        filename="boost_1_66_0.zip";
        extractPath="$buildPath\boost-src"},

    @{name="Qt";
        url="http://download.qt.io/official_releases/qt/5.10/5.10.0/single/qt-everywhere-src-5.10.0.zip";
        filename="qt-everywhere-src-5.10.0.zip";
        extractPath="$buildPath\qt-src"},

    @{name="Python2";
        url="https://www.python.org/ftp/python/2.7.14/python-2.7.14.amd64.msi";
        filename="python-2.7.14.amd64.msi";
        extractPath="$($env:TEMP)\python2";
        installPath="$python2path"}

)

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
        $vcvars = Get-ChildItem -r VsDevCmd.bat | Resolve-Path -Relative
        Pop-Location
    }
    elseif ($version -eq 2015)
    {
        $env:vsVersion = $VS_VERSION[$version]
        $env:msvcver="msvc-14.0"
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio $($VS_VERSION[$version])\Common7\Tools"
        $vcvars = "vcvarsall.bat"
    }
    else
    {
        if ($VS_VERSION -eq 2013) {
            $env:msvcver="msvc-12.0"
        } else {
            $env:msvcver="msvc-11.0"
        }

        $env:vsVersion = $VS_VERSION[$version]
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio $($VS_VERSION[$version])\VC"
        $vcvars = "vcvarsall.bat"
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

Write-Host "* Building RaiBlocks..."

if (!(Test-Path $rootPath)){
    mkdir $rootPath | out-null
}

if (!(Test-Path $repoPath)){
    Write-Host "* Cloning $githubRepo into $repoPath"
    & git clone -q $githubRepo $repoPath
}

if (!(Test-Path $buildPath)){
    Write-Host "* Copying $repoPath into $buildPath"
    copy -Recurse $repoPath $buildPath | out-null
}
cd $buildPath

foreach ($file in $downloads){
    $name = "$($file.name)"
    $filePath = "$downloadPath\$($file.filename)"
    $url = "$($file.url)"
    $extractPath = "$($file.extractPath)"
    $installPath = "$($file.installPath)"
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
            exec { & $filePath } | out-string
        }
    }
    if (!(Test-Path $extractPath) -and ($filePath.Contains(".zip"))) {
        Write-Host "*   Unzipping $filePath into $extractPath..."
        Push-Location
        Unzip $filePath $extractPath
        cd $extractPath
        if (Test-Path *) {
            cd *
        }
        move -force * ..
        Pop-Location
    }
}
#Write-Host "** Please verify build tools are installed before continuing **"
#pause

# add python

if ($env:PYTHONPATH -eq $null) {
    $env:PYTHONPATH = $python2path
}
if ($env:PATH -notmatch '$python2path') {
    $env:PATH=”$python2path;$env:PATH"
}

$buildQtPath = "$buildPath\qt"
$buildQtSrcPath = "$buildPath\qt-src"
if ($env:PATH -notmatch '$buildQtPath') {
    $env:PATH="$env:PATH;$buildQtPath"
}

Set-VsCmd -version 2017
cd $buildPath\boost-src
if (!(Test-Path "project-config.jam")) {
    & ./bootstrap.bat
}
$buildBoostPath = "$buildPath\boost"
$buildBoostBuildPath = "$buildPath\boost-build"
$buildBoostSrcPath = "$buildPath\boost-src"
$buildBoostProjectConfig = "$buildBoostSrcPath\project-config.jam"
If (!(Get-Content $buildBoostProjectConfig | Select-String -Pattern "cl.exe")) {
    Write-Host "* Fixing $buildBoostProjectConfig"
    $clPath = Resolve-Anypath cl.exe
    Write-Host "* Patching project-config.jam with $clPath"
    Invoke-SearchReplace $buildBoostProjectConfig "using msvc ;" "`nusing msvc : $env:vsVersion : `"$clPath`";"
}
if (!(Test-Path "$buildBoostBuildPath\boost")) {
    & ./b2 --prefix=$buildBoostPath --build-dir=$buildBoostBuildPath link=static address-model=64 install
}
if ($env:PATH -notcontains "$buildBoostBuildPath\bin") {
    $env:PATH="$env:PATH;$buildBoostBuildPath\bin"
}
cd $buildQtSrcPath 
if (!(Test-Path $buildQtPath)) {
    & ./configure -shared -opensource -nomake examples -nomake tests -confirm-license -prefix $buildQtPath
}
$env:BOOST_ROOT="$buildBoostPath"
$env:Qt5_DIR="$buildQtPath"
$env:RAIBLOCKS_GUI="ON"
$env:ENABLE_AVX2="ON"
$env:CRYPTOPP_CUSTOM="ON"
& nmake -D BOOST_ROOT="$buildBoostPath" -D Qt5_DIR="$buildQtPath" -D RAIBLOCKS_GUI=ON -D ENABLE_AVX2=ON -D CRYPTOPP_CUSTOM=ON
& nmake install
cd $buildPath
& git submodule update --init --recursive