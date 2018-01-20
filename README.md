# RaiBlocksScripts

This Powershell scripts aims to build RaiBlocks github repo.  
It does this by downloading, unzipping and installing all build tools listed @ https://github.com/clemahieu/raiblocks/wiki/Build-Instructions.

Note Visual Studio 2017 and git is assumed pre-installed, running on either Intel/AMD 32-bit or 64-bit machine.

Some parameters are available to customize your installation:

    [string]$RootPath = "$env:USERPROFILE\Projects\RaiBlocks",
    [string]$GithubRepo = "https://github.com/clemahieu/raiblocks.git",
    [string]$VsVersion = "2017",
    [string]$Bitness = "64",
    [string]$BoostVersion = "1.66.0",
    [string]$QtRelease = "5.10",
    [string]$QtPath = "C:\Qt",
    [string]$CMakePath = $null,
    [string]$ProgramFiles = $env:ProgramFiles,
    [string]$Python2Path = $env:PYTHONPATH

More are available inside the script, but do not have to be changed in most cases.