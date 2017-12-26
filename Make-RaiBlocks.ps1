If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    Write-Error "** RUN SCRIPT AS ADMINISTRATOR **"
    Return
}

clear

$rootPath = "$env:USERPROFILE\dev\raiblocks"  # change this to development path
$downloadPath = "$rootpath\downloads"
$repoPath = "$rootPath\github"
$githubRepo = "https://github.com/clemahieu/raiblocks.git"

$downloads = $(

    @{name="WGET";
        url="https://eternallybored.org/misc/wget/releases/wget-1.19.2-win64.zip";
        filename="wget-1.19.2-win64.zip";
        extractPath="$($env:TEMP)\wget"},

    @{name="NSIS";
        url="https://downloads.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1-setup.exe";
        filename="nsis-3.02.1-setup.exe";
        extractPath="$repoPath\nsis";
        installPath="$((Get-Item "Env:ProgramFiles(x86)").Value)\NSIS\"},

    @{name="Boost";
        url="https://downloads.sourceforge.net/project/boost/boost/1.63.0/boost_1_63_0.zip";
        filename="boost_1_63_0.zip";
        extractPath="$repoPath\boost-src"},

    @{name="Qt";
        url="http://download.qt.io/official_releases/qt/5.10/5.10.0/single/qt-everywhere-src-5.10.0.zip";
        filename="qt-everywhere-src-5.10.0.zip";
        extractPath="$repoPath\qt-src"},

    @{name="CMake";
        url="https://cmake.org/files/v3.10/cmake-3.10.1-win64-x64.zip";
        filename="cmake-3.10.1-win64-x64.zip";
        extractPath="$repoPath\cmake"},

    @{name="Python2";
        url="https://www.python.org/ftp/python/2.7.14/python-2.7.14.amd64.msi";
        filename="python-2.7.14.amd64.msi";
        extractPath="$($env:TEMP)\python2";
        installPath="C:\Python27"}

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
        [parameter(Mandatory=$true, HelpMessage="Enter VS version as 2010, 2012, 2013, 2015, 2017")]
        [ValidateSet(2010,2012,2013,2015,2017)]
        [int]$version
    )
    $VS_VERSION = @{ 2010 = "10.0"; 2012 = "11.0"; 2013 = "12.0"; 2015 = "14.0"; 2017 = "" }
    if ($version -eq 2017)
    {
        Push-Location
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio\2017"
        Set-Location $targetDir
        $vcvars = Get-ChildItem -r VsDevCmd.bat | Resolve-Path -Relative
        Pop-Location
    }
    elseif ($version -eq 2015)
    {
        $targetDir = "C:\Program Files (x86)\Microsoft Visual Studio $($VS_VERSION[$version])\Common7\Tools"
        $vcvars = "vcvarsall.bat"
    }
    else
    {
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
        Write-Host "* SET Env: $($matches[1])`" = `"$($matches[2])`""
        Set-Item -force -path "ENV:\$($matches[1])" -value "$($matches[2])"
      }
    }
    Pop-Location
    write-host "`nVisual Studio $version Command Prompt variables set." -ForegroundColor Yellow
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
            throw "Execution failed with exit code $LASTEXITCODE"
        }
    }
    finally
    {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}

Write-Host " * Building RaiBlocks..."

if (!(Test-Path $repoPath)){
    Write-Host "* Cloning $githubRepo into $repoPath"
    Write-Host
    & git clone -q $githubRepo $repoPath
}
cd $repoPath

foreach ($file in $downloads){
    $name = "$($file.name)"
    $filePath = "$downloadPath\$($file.filename)"
    $url = "$($file.url)"
    $extractPath = "$($file.extractPath)"
    $installPath = "$($file.installPath)"
    $wget = "$env:TEMP\wget.exe"
    Write-Host " * Checking $name"
    if ($file.deleteBeforeDownload -eq $true -and (Test-Path $filePath)) {
        Write-Host "* Deleting old download $filePath"
        del -Force -Recurse $filePath
    }
    if ($file.deleteBeforeExtract -eq $true -and (Test-Path $extractPath)) {
        Write-Host "* Deleting old extraction $extractPath"
        del -Force -Recurse $extractPath
    }

    if (!(Test-Path $filePath)) {
        Write-Host "* Missing $filePath, downloading $url"
        if (Test-Path $wget) {
            Push-Location
            cd $filePath\..
            exec { & $wget --continue $url }
            Pop-Location
        }
        else {
            Invoke-WebRequest -Uri $url -OutFile $filePath
        }
    }
    if (($filePath -match ".msi") -or ($filePath -match ".exe")) {
        if ($installPath -ne "" -and !(Test-Path "$installPath")) {
            Write-Host "* Installing $filepath."
            exec { & $filePath } | out-string
        }
    }
    if (!(Test-Path $extractPath) -and ($filePath.Contains(".zip"))) {
        Write-Host "* Unzipping $filePath into $extractPath..."
        Push-Location
        Unzip $filePath $extractPath
        cd $extractPath
        cd *
        move -force * ..
        Pop-Location
    }
}
Write-Host "** Please verify build tools are installed before continuing **"
pause

# add python
if ($env:PYTHONPATH -eq $null) {
    $env:PYTHONPATH = "C:\Python27"
    $env:PATH=”$env:PATH;C:\Python27”
}

Set-VsCmd -version 2017
cd $repoPath\boost-src
& ./bootstrap.bat

if (Test-Path $repoPath\boost-build) {
    rd -recurse -force $repoPath\boost-build
}
md $repoPath\boost-build

& ./b2 --prefix=$repoPath\boost --build-dir=$repoPath\boost-build link=static "address=model 64" install

cd $repoPath\qt-src
exec { & ./configure -shared -opensource -nomake examples -nomake tests -confirm-license -prefix $repoPath\qt }