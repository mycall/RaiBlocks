param(
    [string]$RootPath = "$env:USERPROFILE\Projects\RaiBlocks",
    [string]$GithubRepo = "https://github.com/clemahieu/raiblocks.git",
    [string]$VsVersion = "2017",
    [string]$Bitness = "64",
    [string]$BoostVersion = "1.66.0",
    [string]$QtRelease = "5.10",
    [string]$QtPath = "C:\Qt",
    [string]$CMakePath = $null,
    [string]$ProgramFiles = $env:ProgramFiles,
    [string]$Python2Path = $env:PYTHONPATH,
    [boolean]$ForceFullBuild = $true
)

If (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")){
    Write-Error "** RUN SCRIPT AS ADMINISTRATOR IF INSTALLING DEVTOOLS **"
    Return
}

if (-NOT (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio")) {
    Write-Error "** Visual Studio 2012 or newer is required. **"
    Return
}

clear

$env:BOOST_DEBUG = "ON"
$env:BOOST_CUSTOM = "ON"
$env:RAIBLOCKS_GUI = "ON"
$env:ENABLE_AVX2 = "ON"
$env:CRYPTOPP_CUSTOM = "ON"
$env:BOOST_THEADING = "multi"  # (multi|single)
$env:BOOST_RUNTIME_LINK = "static,shared"    # (static|shared)
$env:BOOST_LINK = "static"
$env:BOOST_ARCH = "x86"


$bitArch1 = $(if ($Bitness -eq "64") {"x64"} else {"x86"})
$bitArch2 = $(if ($Bitness -eq "64") {"win64"} else {"win32"})
$bitArch3 = $(if ($Bitness -eq "64") {"amd64"} else {""})
$bitArch4 = $(if ($Bitness -eq "64") {"-x64"} else {""})
$boostBaseName = "boost_" + $BoostVersion.Replace(".","_")
$boostBaseNameShort = "boost-" + $BoostVersion.Replace(".0","").Replace(".","_")
$QtReleaseFull = "$QtRelease.0"
$downloadPath = "$RootPath\downloads"
$repoPath = "$RootPath\github"
$buildPath = "$RootPath\github-build"
$ProgramFiles32 = $(Get-Item "env:programfiles(x86)").Value

if ([string]::IsNullOrEmpty($Python2Path)) { 
    $Python2Path = $env:PYTHONHOME
}
if ([string]::IsNullOrEmpty($Python2Path)) { 
    $Python2Path = 'C:\Python27'
}

$downloads = $(
    @{name="wget";
        url="https://eternallybored.org/misc/wget/releases/wget-1.19.2-win$Bitness.zip"; 
        filename="wget-1.19.2-win$Bitness.zip";
        extractPath="$env:TEMP\wget"},
    @{name="7zip";
        url="http://www.7-zip.org/a/7z1800$bitArch4.exe"; 
        filename="7z1800$bitArch4.exe";
        installPath="$ProgramFiles\7-Zip";
        addPath="$ProgramFiles\7-Zip"},
    @{name="Python2";
        url="https://www.python.org/ftp/python/2.7.14/python-2.7.14.$bitArch3.msi";
        filename="python-2.7.14.$bitArch3.msi";
        extractPath="$env:TEMP\python2";
        installPath="$Python2Path";
        addPath="$Python2Path"},
    @{name="NSIS";
        url="https://downloads.sourceforge.net/project/nsis/NSIS%203/3.02.1/nsis-3.02.1-setup.exe";
        filename="nsis-3.02.1-setup.exe";
        installPath="$ProgramFiles32\NSIS\";
        addPath="$ProgramFiles32\NSIS\bin"},
    @{name="MS MPI 8.1.1";
        url="https://download.microsoft.com/download/9/E/D/9ED82A62-4235-4003-A59A-9F6246073F2E/MSMpiSetup.exe";
        filename="MSMpiSetup.exe";
        installPath="$ProgramFiles\Microsoft MPI";
        addPath="$ProgramFiles\Microsoft MPI\Bin"},
    @{name="MS MPI 8.1.1 SDK";
        url="https://download.microsoft.com/download/9/E/D/9ED82A62-4235-4003-A59A-9F6246073F2E/msmpisdk.msi";
        filename="msmpisdk.msi";
        installPath="$ProgramFiles32\Microsoft SDKs\MPI\";
        addPath="$ProgramFiles32\Microsoft SDKs\MPI\Bin"},
    @{name="Qt";
        url="http://download.qt.io/official_releases/qt/$QtRelease/$QtReleaseFull/qt-opensource-windows-x86-$QtReleaseFull.exe";
        filename="qt-opensource-windows-x86-$QtReleaseFull.exe";
        installPath="$QtPath\Qt$QtReleaseFull";
        addPath="$QtPath\Qt$QtReleaseFull\$QtReleaseFull\msvc$VsVersion`_$Bitness\bin;$QtPath\Qt$QtReleaseFull\Tools\QtCreator\bin";
        installComment="Please check msvc$VsVersion $Bitness-bit Prebuilt Components";
        linkedInstallName="qt";
        linkedInstallPath="$QtReleaseFull\msvc$VsVersion`_$Bitness";
    },
    #@{name="Qt-src";
    #    url="http://download.qt.io/official_releases/qt/$QtRelease/$QtReleaseFull/single/qt-everywhere-src-$QtReleaseFull.zip";
    #    filename="qt-everywhere-src-$QtReleaseFull.zip";
    #    extractPath="$buildPath\qt-src"},
    @{name="CMake";
        url="https://cmake.org/files/v3.10/cmake-3.10.2-$bitArch2-$bitArch1.zip";
        filename="cmake-3.10.2-$bitArch2-$bitArch1.zip";
        collapseDir=$true;
        extractpath="$buildpath\cmake"},
    @{name="Boost";
        url="https://dl.bintray.com/boostorg/release/$BoostVersion/source/$boostBaseName.zip";
        filename="$boostBaseName.zip";
        collapseDir=$true;
        extractPath="$buildPath\boost"}
)

$buildQtPath = "$buildPath\qt"
$buildQtSrcPath = "$buildPath\qt-src"

$env:BOOST_ROOT="$buildPath\boost"
$env:BOOST_BUILD_ROOT=$env:BOOST_ROOT
$env:BOOST_TARGET_ROOT=$env:BOOST_ROOT
$env:Qt5_DIR=$buildQtPath
$env:FINDBOOST_PATH = ""

$boostRoot = "$env:BOOST_ROOT"
$boostBuildDir = "$env:BOOST_BUILD_ROOT\build"
$boostPrefixDir = "$env:BOOST_TARGET_ROOT"
$boostIncludeDir = "$env:BOOST_TARGET_ROOT\include\$boostBaseNameShort\boost"
$boostLibDir = "$env:BOOST_TARGET_ROOT\stage\lib"
#$boostLibDir2 = "$env:BOOST_TARGET_ROOT\libs"
$boostBinPath = "$env:BOOST_ROOT\bin"
$boostProjectConfig = "$env:BOOST_ROOT\project-config.jam"
$boostUserConfig = "$env:BOOST_ROOT\tools\build\src\user-config.jam"
$boostProc = "j$processors"


##############################################################################

#Add-Type -AssemblyName System.IO.Compression.FileSystem
function Unzip
{
    param([string]$zipfile, [string]$outpath)
    $backupErrorActionPreference = $script:ErrorActionPreference
    $script:ErrorActionPreference = "Stop"
    if (Test-Path $outpath) {
        rmdir -recursive -force $outpath | out-null
    }
    if (!(Test-Path $outpath)) {
        mkdir -force $outpath | out-null
    }
    7z x $zipfile -o"$outpath" -r | out-null
    #[System.IO.Compression.ZipFile]::OpenRead($zipfile).Entries.Name | Out-Null # tests for corruption
    #[System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $outpath)
    $script:ErrorActionPreference = $backupErrorActionPreference
}

function Set-VsCmd
{
    param(
        [parameter(Mandatory=$true, HelpMessage="Enter VS version as 2012, 2013, 2015, 2017")]
        [ValidateSet(2012,2013,2015,2017)]
        [int]$version
    )
    $VS_VERSION = @{ 2012 = "11.0"; 2013 = "12.0"; 2015 = "14.0"; 2017 = "14.1" }
    $VS_VERSION2= @{ 2012 = "11"; 2013 = "12"; 2015 = "14"; 2017 = "15" }

    if ($version -ge 2015)
    {
        $env:VsVersion = $VS_VERSION[$version]
        $env:msvcver="msvc-$env:VsVersion"
        Push-Location
        $targetDir = $(if ($version -eq 2015) { "$ProgramFiles32\Microsoft Visual Studio $env:VsVersion" } else { "$ProgramFiles32\Microsoft Visual Studio\$version" })
        Set-Location $targetDir
        $vcvars = Get-ChildItem -Recurse vcvars$Bitness.bat | Resolve-Path -Relative 
        $env:CMAKE_BIN = "$CMakePath\bin"
        if ([string]::IsNullOrEmpty($CMakePath)) {
            $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'})\bin"
        }
        $env:FINDBOOST_PATH = "$(Get-ChildItem -Recurse FindBoost.cmake | Resolve-Path)" | Convert-Path 
        $env:VS_ARCH = "Visual Studio $($VS_VERSION2[$version]) $version"
        Pop-Location
    }
    else
    {
        $env:VsVersion = $VS_VERSION[$version]
        $env:msvcver="msvc-$($VS_VERSION[$version])"
        $env:VS_ARCH = "Visual Studio $($VS_VERSION2[$version]) $version"
        Push-Location
        $targetDir = "$ProgramFiles32\Microsoft Visual Studio $($VS_VERSION[$version])\VC"
        Set-Location $targetDir
        $vcvars = "vcvarsall.bat"
        $env:CMAKE_BIN = "$(Get-ChildItem CMake -Recurse | where {$_.Parent -match 'CMake'} | Resolve-Path -Relative)\bin"
        Pop-Location
    }
  
    if (!(Test-Path (Join-Path $targetDir $vcvars))) {
        "* Error: Visual Studio $version not installed"
        return
    }
    if ($Bitness -eq "64") { 
        Write-Host "*   Setting 64-bit mode"
        $vcvars = $($vcvars -replace "32", "64") + " amd64"
        $env:VS_ARCH += " Win64"
    }
    Write-host "* Running $targetDir $vcvars"
    Push-Location $targetDir
    $vcvars += "&set"
    cmd /c $vcvars |
    ForEach-Object {
      if ($_ -match "(.*?)=(.*)") {
        Set-Item -force -path "ENV:\$($matches[1])" -value "$($matches[2])"
      }
    }
    Pop-Location
    write-host "*   Visual Studio $version environment variables set."
}

function Resolve-Anypath
{
    param ($file, $find)
    $paths = (".;" + $env:PATH).Split(";")
    foreach ($path in $paths) {
        $testPath = Join-Path $path $file
        if ((Test-Path $testPath) -and ($testPath -match $find)) {
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

    $sb = [ScriptBlock]::Create($ScriptBlock)

    Write-Host "*   Calling $sb"

    $backupErrorActionPreference = $script:ErrorActionPreference

    $script:ErrorActionPreference = "Continue"
    try
    {
        & $ScriptBlock 2>&1 | ForEach-Object -Process `
            {
                if ($_ -is [System.Management.Automation.ErrorRecord]) { "$StderrPrefix$_" } else { "$_" }
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
    $latestTs = dir "$ProgramFiles32\Microsoft SDKs\TypeScript\" | Sort | Select -last 1 $_.Name
    $fso = New-Object -ComObject "Scripting.FileSystemObject"
    $shortpaths = @();
    $originalPaths = [environment]::GetEnvironmentVariable("path", "Machine").Split(";")
    foreach ($path in $originalPaths) {
        $fpath = [System.IO.Path]::GetFullPath("$path");
        if ($fpath.StartsWith("$ProgramFiles32\Microsoft SDKs\TypeScript\")) {
            $fpath = "$ProgramFiles\Microsoft SDKs\TypeScript\$latestTs\";
        }
        $fspath = $fso.GetFolder("$fpath").ShortPath;
        $foundIdx = $shortpaths.IndexOf($fspath);
        if ($foundIdx -gt -1) {	continue; }
        write-host $fpath  -->  $fspath;
        $shortpaths += $fspath;
    }
    $env:Path = $shortpaths -join ";"
}

function Add-EnvPath {
    param
    (
        [string] $Item = "",
        [bool] $Append = $true
    )
    Write-Host "*   Adding to PATH $Item"
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

Write-Host "* Preparing RaiBlocks build tools..."


if (!([string]::IsNullOrEmpty($env:PATH_BACKUP))) {
    Write-Host "* Restoring previous path backup."
    $env:PATH = $env:PATH_BACKUP
}
$env:PATH_BACKUP = $env:PATH


if (!(Test-Path $RootPath)){
    mkdir $RootPath | out-null
}

if (!(Test-Path $repoPath)){
    Write-Host "* Cloning $GithubRepo into $repoPath"
    $backupErrorActionPreference = $script:ErrorActionPreference
    $script:ErrorActionPreference = "Stop"
    & git clone -q $GithubRepo $repoPath
    $script:ErrorActionPreference = $backupErrorActionPreference
}

if ((Test-Path $buildPath) -and ($ForceFullBuild -eq $true)) {
    Write-Host "* Forcing full build, deleting $buildPath"
    if (Test-Path "$buildPath\qt") {
        (Get-Item $buildPath\qt).Delete() | out-null
    }
    if (Test-Path "$RootPath\empty") {
        rmdir "$RootPath\empty" | out-null
    }
    mkdir "$RootPath\empty" | out-null
    robocopy "$RootPath\empty" $buildPath /mir | out-null 
    rmdir $buildPath | out-null
    rmdir "$RootPath\empty" | out-null
}

if (!(Test-Path $buildPath)){
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
    $collapseDir = $(if ($file.collapseDir) {$true} else {$false})
    $wget = "$env:TEMP\wget\wget.exe"
    $targetDir = $(if (!([string]::IsNullOrEmpty($installPath))) {$installPath} else {$extractPath})
    Write-Host "* Checking $name is installed in $targetDir"

    if (!(Test-Path $downloadPath)) {
        Write-Host "* Creating $downloadPath"
        mkdir $downloadPath
    }

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
            exec { & $wget --tries=50 --retry-connrefused --no-verbose --continue $url }
            Pop-Location
        }
        else {
            Invoke-WebRequest -Uri $url -OutFile $filePath
        }
    }
    if (($filePath -match ".msi") -or ($filePath -match ".exe")) {
        if ((!([string]::IsNullOrEmpty($installPath))) -and !(Test-Path "$installPath")) {
            Write-Host "*   Installing $filepath."
            if (!([string]::IsNullOrEmpty($installComment))) {
                Write-Host "*** $installComment ***"
            }
            Start-Process "$filePath" -Wait
        }
    }
    if (($filePath -match ".zip") -and (!(Test-Path $extractPath))) {
        Write-Host "*   Unzipping $filePath into $extractPath..."
        Push-Location
        Unzip $filePath $extractPath
        cd $extractPath
        if (($collapseDir) -and ((Get-ChildItem | ?{ $_.PSIsContainer }).Length -eq 1)) {
            $dirName = $(Get-ChildItem | ?{ $_.PSIsContainer } | Select-Object -First 1).Name
            move -force $dirName\* .
            rmdir -recurse $dirName
        }
        Pop-Location
    }
    if ((!([string]::IsNullOrEmpty($linkedInstallName))) -and (Test-Path "$installPath\$linkedInstallPath") -and (!(Test-Path "$buildPath\$linkedInstallName"))) {
        Write-Host "*   Creating symbolic link from $buildPath\$linkedInstallName to $installPath\$linkedInstallPath"
        Push-Location
        cd $buildPath
        New-Item -ItemType SymbolicLink -Name $linkedInstallName -Target $installPath\$linkedInstallPath | out-null
        Pop-Location
    }
    if ((!([string]::IsNullOrEmpty($addPath))) -and (!($env:PATH.Contains($addPath)))) {
        Add-EnvPath -Item $addPath
    }
}

##############################################################################

Write-Host "* Building RaiBlocks..."

# add python to path
if ([string]::IsNullOrEmpty($env:PYTHONPATH)) {
    Write-Host "*   Set PYTHONPATH=$Python2Path"
    $env:PYTHONPATH = $Python2Path
}

## setup Visual Studio path
Set-VsCmd -version $VsVersion

# check for custom cmake
if (Test-Path "$buildpath\cmake") {
    $env:CMAKE_BIN = "$buildpath\cmake\bin"
}

# add cmake to path
if (!($env:PATH.Contains($env:CMAKE_BIN))) {
    Add-EnvPath -Item $env:CMAKE_BIN
}

# add Boost.Build\bin to path
if (!($env:PATH.Contains($boostBinPath))) {
    Add-EnvPath -Item $boostBinPath
}

# patch FindBoost.cmake with repo version
If ((!([string]::IsNullOrEmpty($env:FINDBOOST_PATH))) -and !(Get-Content $env:FINDBOOST_PATH | Select-String -Pattern "_boost_AAM_TAG")) {
    Set-ItemProperty -Path $env:FINDBOOST_PATH -Name IsReadOnly -Value $false
    Write-Host "*   Copying $buildPath\FindBoost.cmake to $env:FINDBOOST_PATH"
    copy "$buildPath\FindBoost.cmake" "$env:FINDBOOST_PATH"
}

# make BOOST
cd $env:BOOST_ROOT
if (!(Test-Path "project-config.jam")) {
    Write-Host "* Defining BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE in boost\config\user.hpp"
    Invoke-SearchReplace "$env:BOOST_ROOT\boost\config\user.hpp" "// define this to locate a compiler config file:" "#define BOOST_CONFIG_SUPPRESS_OUTDATED_MESSAGE`n// define this to locate a compiler config file:"
    & ./bootstrap.bat 
    # use these if not building "complete" --with-libraries=date_time,filesystem,system,log,thread,program_options,regex,chrono,atomic,python
}

If (!(Get-Content $boostProjectConfig | Select-String -Pattern "cl.exe")) {
    Write-Host "* Fixing $boostProjectConfig"
    $clPath = Resolve-Anypath -file  "cl.exe" -find "HostX64.$bitArch1"
    $ar = $(if ($Bitness -eq 64) {"<address-model>64 ; "} else {""})
    $rpl = "using msvc : $env:VsVersion : `"$clPath`" ;"
    #$rpl = "using msvc : $env:VsVersion : `"$clPath`" ; `nusing python : 2.7 : $Python2Path : $Python2Path\include : $Python2Path\libs : $ar".Replace("\", "\\")
    Write-Host "* Patching $boostProjectConfig with $rpl"
    Invoke-SearchReplace $boostProjectConfig "using msvc ;" $rpl
    if (!(Test-Path $boostUserConfig)) {
        Add-Content $boostUserConfig "using mpi ; "
    }
}

if (!(Test-Path "$boostBuildDir\boost")) {
    exec { & ./b2 "--prefix=$($boostPrefixDir)" `
        architecture=$($env:BOOST_ARCH) `
        toolset=$($env:msvcver) `
        variant=debug,release `
        link=$($env:BOOST_LINK) `
        address-model=$Bitness `
        $(if (!([string]::IsNullOrEmpty($env:BOOST_RUNTIME_LINK))) {"runtime-link=$env:BOOST_RUNTIME_LINK"} else {""}) `
        $(if (!([string]::IsNullOrEmpty($env:BOOST_THEADING))) {"threading=$env:BOOST_THEADING"} else {""}) `
        --debug-configuration --build-type=complete msvc stage install }
        #--layout=versioned `
        # "--build-dir=$($boostBuildDir)"
}

## Make Qt source when available
if (Test-Path $buildQtSrcPath) {
    cd $buildQtSrcPath 
    if (!(Test-Path $buildQtPath)) {
        & ./configure -shared -opensource -nomake examples -nomake tests -confirm-license -prefix $env:Qt5_DIR
    }
    & nmake 
    & nmake install
}

cd $buildPath

if (!(Get-Content "CMakeLists.txt" | Select-String -Pattern "find_package .Boost $BoostVersion")) {
    Write-Host "* Fixing CMakeLists.txt with Boost $BoostVersion"
    Invoke-SearchReplace "CMakeLists.txt" "find_package \(Boost \d+\.\d+\.\d+" "find_package (Boost $BoostVersion"
}

exec { & git submodule update --init --recursive }
if (Test-Path CMakeCache.txt) {
    del CMakeCache.txt | out-null
}
if (Test-Path CMakeFiles) {
    rm -Force -Recurse CMakeFiles
}
if (Test-Path CMakeCache.txt) {
    rm -Force CMakeCache.txt
}
if (Test-Path build) {
    rm -Force -Recurse build
}
mkdir build | out-null
cd build
exec { & cmake -G "$env:VS_ARCH" `
    -D Qt5_DIR=$($env:Qt5_DIR) `
    -D Boost_USE_STATIC_LIBS=ON `
    -D BOOST_ROOT=$($env:BOOST_ROOT) `
    -D BOOST_INCLUDEDIR=$($boostIncludeDir) `
    -D BOOST_LIBRARYDIR=$($boostLibDir) `
    -D Boost_DEBUG=$($env:BOOST_DEBUG) `
    -D RAIBLOCKS_GUI=$($env:RAIBLOCKS_GUI) `
    -D CRYPTOPP_CUSTOM=$($env:CRYPTOPP_CUSTOM) `
    -D ENABLE_AVX2=$($env:ENABLE_AVX2) `
    -D BOOST_CUSTOM=$($env:BOOST_CUSTOM) ..\CMakeLists.txt }
cd ..
#cmake
if (Test-Path ALL_BUILD.vcxproj) {
    devenv /Rebuild Debug ALL_BUILD.vcxproj
}
#$env:PATH = $env:PATH_BACKUP