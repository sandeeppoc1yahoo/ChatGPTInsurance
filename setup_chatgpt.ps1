<#
.SYNOPSIS
  Generates openapi-for-chatgpt.json with your live APIM URL for GPT Actions import.

.EXAMPLE
  .\setup_chatgpt.ps1 -ApimName qqtest0622-apim
#>
param(
    [string]$ApimName = "qqtest0622-apim"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$baseUrl = "https://$ApimName.azure-api.net/quote"
$schemaUrl = "$baseUrl/openapi.json"

# Fetch live schema from deployed API (includes correct server URL)
$spec = Invoke-RestMethod -Uri $schemaUrl -Method GET
$outFile = Join-Path $PSScriptRoot "openapi-for-chatgpt.json"
$spec | ConvertTo-Json -Depth 20 | Set-Content $outFile -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " ChatGPT / GPT Store Setup" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "1. Go to: https://chatgpt.com/gpts/editor" -ForegroundColor White
Write-Host "2. Create a GPT, name it 'Quick Quote Travel Insurance'" -ForegroundColor White
Write-Host "3. Instructions tab: paste contents of chatgpt_instructions.txt" -ForegroundColor White
Write-Host "4. Actions -> Create new action -> Import from URL:" -ForegroundColor White
Write-Host "   $schemaUrl" -ForegroundColor Cyan
Write-Host "   (or upload: openapi-for-chatgpt.json)" -ForegroundColor Gray
Write-Host "5. Authentication: None" -ForegroundColor White
Write-Host "6. Privacy policy (required for GPT Store): use any public URL" -ForegroundColor White
Write-Host "7. Save -> Publish -> Public (GPT Store)" -ForegroundColor White
Write-Host ""
Write-Host "Test prompt in ChatGPT:" -ForegroundColor White
Write-Host '  "Quote travel insurance for 10 days in Japan, age 35, Standard coverage"' -ForegroundColor Gray
Write-Host ""
Write-Host "Schema saved to: $outFile" -ForegroundColor Gray
Write-Host ""
