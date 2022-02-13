# This wrapper can run in two different ways.
#  1) without an input it will run all the files based on git diff comparing changes since last commit - used on runs triggered by push
#  2) with a regex input specifying a expression for the base name of the subscription files - used for runs triggered by workflow dispatch

[CmdletBinding()]
param (
    [Parameter()]
    [string]
    $filePattern = ''
)

$rootPath = & git rev-parse --show-toplevel

$fileRoot = "$rootPath/teams"

if (!$filePattern) {
    $files = & git diff HEAD^ --name-only $fileRoot
}
else {
    $allTeamFiles = Get-ChildItem -Path "$($fileRoot)/*" -Include *.json -Recurse -File
    $files = $allTeamFiles | Where-Object BaseName -Like $filePattern # Regex matching on basename (filename without extension)
    $files = $files.FullName | ForEach-Object { $_.Split("$rootpath/")[1] } # To get filenames on format subscriptions/<type>/<filename>.json to match git diff format
}

Write-Output ">>>>>>>>>> Summary of files to provision: <<<<<<<<<<"
Write-Output ""
if (!$files) {
    Write-Output "No access packages to process"
}
else {
    foreach ($file in $files) {
        Write-Output $file
    }
}
Write-Output ""
Write-Output ">>>>>>>>>> Summary END <<<<<<<<<<"

foreach($file in $files){
    [string]$absolutePath = $rootPath +"/" +$file
    & $PSScriptRoot/create-accessgroup.ps1 -TeamJsonPath $absolutePath -appID $env:appId -appSecret $env:appSecret -tenantID $env:tenantId
}

