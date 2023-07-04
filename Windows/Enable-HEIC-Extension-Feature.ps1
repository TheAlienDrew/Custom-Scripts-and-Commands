<#
  .SYNOPSIS
  Script downloads and installs all extensions needed for viewing/editing HEIF/HEVC/HEIC file types.

  .DESCRIPTION
  Version 2.0.9
  
  Since old manufacturer installed Windows installations don't always include this support, this script is handy to turn
  on HEIC file support without needing admin access or even the Microsoft Store.
  
  NOTE: This is a per user profile thing, so this needs to be done in all profiles where .HEIC aren't working.
  
  * Some Windows computers (e.g. Dell) support installation of the "HEVC Video Extensions from Device Manufacturer"
    app for free from the app store, but it's not something you can search for to install.
  * HEIC is a proprietary file type by Apple which combines the use of HEIF/HEVC in an HEIC container.
  * Microsoft Photos is required for the extensions to work.

  .PARAMETER Help
  Brings up this help page, but won't run script.

  .INPUTS
  Nothing other than the help flag.

  .OUTPUTS
  Display errors if any, otherwise, should return boolean result of script.

  .EXAMPLE
  PS> .\Enable-HEIC-Extension-Feature.ps1

  .LINK
  Third-Party API for Downloading Microsoft Store Apps: https://store.rg-adguard.net/

  .LINK
  Script downloaded from: https://github.com/TheAlienDrew/OS-Scripts/blob/main/Windows/Enable-HEIC-Extension-Feature.ps1
#>

# Copyright (C) 2023  Andrew Larson (thealiendrew@gmail.com)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

param(
  [Alias("h")]
  [switch]$Help
)

# check for parameters and execute accordingly
if ($Help.IsPresent) {
  Get-Help $MyInvocation.MyCommand.Path
  exit
}

# Constants
Set-Variable -Name PHOTOS_APPX_PACKAGEFAMILYNAME -Option Constant -Value "Microsoft.Windows.Photos_8wekyb3d8bbwe" # ProductId = 9WZDNCRFJBH4
Set-Variable -Name PHOTOS_APPX_NAME -Option Constant -Value ${PHOTOS_APPX_PACKAGEFAMILYNAME}.split('_')[0]
Set-Variable -Name HEIF_APPX_PACKAGEFAMILYNAME -Option Constant -Value "Microsoft.HEIFImageExtension_8wekyb3d8bbwe" # ProductId = 9PMMSR1CGPWG
Set-Variable -Name HEIF_APPX_NAME -Option Constant -Value ${HEIF_APPX_PACKAGEFAMILYNAME}.split('_')[0]
Set-Variable -Name HEVC_APPX_PACKAGEFAMILYNAME -Option Constant -Value "Microsoft.HEVCVideoExtension_8wekyb3d8bbwe" # ProductId = 9N4WGH0Z6VHQ
Set-Variable -Name HEVC_APPX_NAME -Option Constant -Value ${HEVC_APPX_PACKAGEFAMILYNAME}.split('_')[0]

# Functions

# Input = PackageFamilyName of Microsoft Store app
# Output = Array of paths to successfully downloaded packages (app of PackageFamilyName and its dependencies)
# Errors = Display in console
function Download-AppxPackage {
  $DownloadedFiles = @()
  $errored = $false
  $allFilesDownloaded = $true

  $apiUrl = "https://store.rg-adguard.net/api/GetFiles"
  $versionRing = "Retail"

  $architecture = switch ($env:PROCESSOR_ARCHITECTURE) {
    "x86" { "x86" }
    { @("x64", "amd64") -contains $_ } { "x64" }
    "arm" { "arm" }
    "arm64" { "arm64" }
    default { "neutral" } # should never get here
  }

  $AppxPackageFamilyName = $args[0]
  $AppxName = $AppxPackageFamilyName.split('_')[0]

  $downloadFolder = Join-Path $env:TEMP "StoreDownloads"
  if (!(Test-Path $downloadFolder -PathType Container)) {
    [void](New-Item $downloadFolder -ItemType Directory -Force)
  }

  $body = @{
    type = 'PackageFamilyName'
    url  = $AppxPackageFamilyName
    ring = $versionRing
    lang = 'en-US'
  }

  $raw = $null
  try {
    $raw = Invoke-RestMethod -Method Post -Uri $apiUrl -ContentType 'application/x-www-form-urlencoded' -Body $body
  } catch {
    $errorMsg = "An error occurred: " + $_
    Write-Host $errorMsg
    $errored = $true
    return $false
  }

  # hashtable of packages by $name
  #  > values = hashtables of packages by $version
  #    > values = arrays of packages as objects (containing: url, filename, name, version, arch, publisherId, type)
  [Collections.Generic.Dictionary[string, Collections.Generic.Dictionary[string, array]]] $packageList = @{}
  # populate $packageList
  $patternUrlAndText = '<tr style.*<a href=\"(?<url>.*)"\s.*>(?<text>.*\.(app|msi)x.*)<\/a>'
  $raw | Select-String $patternUrlAndText -AllMatches | % { $_.Matches } | % {
    $url = ($_.Groups['url']).Value
    $text = ($_.Groups['text']).Value
    $textSplitUnderscore = $text.split('_')
    $name = $textSplitUnderscore.split('_')[0]
    $version = $textSplitUnderscore.split('_')[1]
    $arch = ($textSplitUnderscore.split('_')[2]).ToLower()
    $publisherId = ($textSplitUnderscore.split('_')[4]).split('.')[0]
    $textSplitPeriod = $text.split('.')
    $type = ($textSplitPeriod[$textSplitPeriod.length - 1]).ToLower()

    # create $name hash key hashtable, if it doesn't already exist
    if (!($packageList.keys -match ('^' + [Regex]::escape($name) + '$'))) {
      $packageList["$name"] = @{}
    }
    # create $version hash key array, if it doesn't already exist
    if (!(($packageList["$name"]).keys -match ('^' + [Regex]::escape($version) + '$'))) {
      ($packageList["$name"])["$version"] = @()
    }
 
    # add package to the array in the hashtable
    ($packageList["$name"])["$version"] += @{
      url         = $url
      filename    = $text
      name        = $name
      version     = $version
      arch        = $arch
      publisherId = $publisherId
      type        = $type
    }
  }

  # an array of packages as objects, meant to only contain one of each $name
  $latestPackages = @()
  # grabs the most updated package for $name and puts it into $latestPackages
  $packageList.GetEnumerator() | % { ($_.value).GetEnumerator() | Select-Object -Last 1 } | % {
    $packagesByType = $_.value
    $msixbundle = ($packagesByType | ? { $_.type -match "^msixbundle$" })
    $appxbundle = ($packagesByType | ? { $_.type -match "^appxbundle$" })
    $msix = ($packagesByType | ? { ($_.type -match "^msix$") -And ($_.arch -match ('^' + [Regex]::Escape($architecture) + '$')) })
    $appx = ($packagesByType | ? { ($_.type -match "^appx$") -And ($_.arch -match ('^' + [Regex]::Escape($architecture) + '$')) })
    if ($msixbundle) { $latestPackages += $msixbundle }
    elseif ($appxbundle) { $latestPackages += $appxbundle }
    elseif ($msix) { $latestPackages += $msix }
    elseif ($appx) { $latestPackages += $appx }
  }

  # download packages
  $latestPackages | % {
    $url = $_.url
    $filename = $_.filename
    # TODO: may need to include detection in the future of expired package download URLs..... in the case that downloads take over an hour to complete

    $downloadFile = Join-Path $downloadFolder $filename

    # If file already exists, ask to replace it
    if (Test-Path $downloadFile) {
      Write-Host "`"${filename}`" already exists at `"${downloadFile}`"."
      $confirmation = ''
      while (!(($confirmation -eq 'Y') -Or ($confirmation -eq 'N'))) {
        $confirmation = Read-Host "`nWould you like to re-download and overwrite the file at `"${downloadFile}`" (Y/N)?"
        $confirmation = $confirmation.ToUpper()
      }
      if ($confirmation -eq 'Y') {
        Remove-Item -Path $downloadFile -Force
      } else {
        $DownloadedFiles += $downloadFile
      }
    }

    if (!(Test-Path $downloadFile)) {
      Write-Host "Attempting download of `"${filename}`" to `"${downloadFile}`" . . ."
      $fileDownloaded = $null
      try {
        Invoke-WebRequest -Uri $url -OutFile $downloadFile
        $fileDownloaded = $?
      } catch {
        $errorMsg = "An error occurred: " + $_
        Write-Host $errorMsg
        $errored = $true
        break $false
      }
      if ($fileDownloaded) { $DownloadedFiles += $downloadFile }
      else { $allFilesDownloaded = $false }
    }
  }

  if ($errored) { Write-Host "Completed with some errors." }
  if (-Not $allFilesDownloaded) { Write-Host "Warning: Not all packages could be downloaded." }
  return $DownloadedFiles
}

# Input = Product ID of Microsoft Store app
# Output = Downloads and installs app of ID and its dependencies
# Errors = Display in console
function Install-AppxPackage {
  $errored = $false

  $AppxPackageFamilyName = $args[0]

  try {
    [Array]$appxPackages = Download-AppxPackage $AppxPackageFamilyName
    for ($i = 0; $i -lt $appxPackages.count; $i++) {
      $appxFilePath = $appxPackages[$i]
      $appxFileName = Split-Path $appxFilePath -leaf

      # only install package if not already installed
      $appxPackageName = $appxFileName.split('_')[0]
      if (Get-AppxPackage -Name $appxPackageName) {
        Write-Host "`"${appxPackageName}`" already installed."
      } else {
        Add-AppxPackage -Path $appxFilePath
        if ($?) { Write-Host "`"${appxPackageName}`" installed successfully." }
        else { throw "`"${appxPackageName}`" failed to install." }
      }
    }
  } catch {
    $errorMsg = "An error occurred: " + $_
    Write-Host $errorMsg
    $errored = $true
  }
  Write-Host ""

  return (-Not $errored)
}

# MAIN

# make sure we are online first
if (-Not $(Test-NetConnection -InformationLevel Quiet)) {
  Write-Host "Please make sure you're connected to the internet, then try again."
  exit 1
}

# need to make sure the logged in user is running the script
$powershellUser = $(whoami)
$loggedInUser = $(Get-WMIObject -class Win32_ComputerSystem).username.toString()
if ($powershellUser -ne $loggedInUser) {
  Write-Host "Please make sure the script is running as user (e.g. don't run as admin)."
  exit 1
}

# Install apps needed, if they're not already installed
$installedApps = 0
try {
  # First, Microsoft Photos
  if (Get-AppxPackage -Name ${PHOTOS_APPX_NAME}) {
    Write-Host "`"Microsoft Photos`" already installed.`n"
  } else {
    $installedApps++
    Write-Host 'Installing "Microsoft Photos"...'
    if (-Not (Install-AppxPackage ${PHOTOS_APPX_PACKAGEFAMILYNAME})) { throw "Couldn't install `"Microsoft Photos`"" }
  }
  # Then, HEIF Image Extensions
  if (Get-AppxPackage -Name ${HEIF_APPX_NAME}) {
    Write-Host "`"HEIF Image Extensions`" already installed.`n"
  } else {
    $installedApps++
    Write-Host 'Installing "HEIF Image Extensions"...'
    if (-Not (Install-AppxPackage ${HEIF_APPX_PACKAGEFAMILYNAME})) { throw "Couldn't install `"HEIF Image Extensions`"" }
  }
  # Lastly, HEVC Video Extensions from Device Manufacturer
  if (Get-AppxPackage -Name ${HEVC_APPX_NAME}) {
    Write-Host "`"HEVC Video Extensions from Device Manufacturer`" already installed.`n"
  } else {
    $installedApps++
    Write-Host 'Installing "HEVC Video Extensions from Device Manufacturer"...'
    if (-Not (Install-AppxPackage ${HEVC_APPX_PACKAGEFAMILYNAME})) { throw "Couldn't install `"HEVC Video Extensions from Device Manufacturer`"" }
  }
} catch {
  $errorMsg = "An error occurred: " + $_
  Write-Host $errorMsg
  exit 1
}

if (Get-AppxPackage -Name "Microsoft.HEVCVideoExtension") {
  if ($installedApps -gt 0) { Write-Host "HEIC extension feature enabled successfully." }
  else { Write-Host "HEIC extension feature was already enabled, no changes made." }
  exit 0
} else {
  Write-Host "Something went wrong, HEIC extension feature NOT enabled."
  exit 1
}
