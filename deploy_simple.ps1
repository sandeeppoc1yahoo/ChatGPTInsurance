<#
.SYNOPSIS
  Simple one-click deploy: Python Function + APIM (Consumption) for Quick Quote.

.DESCRIPTION
  Creates (or updates) a resource group, Azure Function (Python, free consumption plan),
  and APIM Consumption gateway. No Docker, no Container Apps, no App Service VM needed.

  Public UI URL:  https://<apim-name>.azure-api.net/quote/ui
  Public API URL: https://<apim-name>.azure-api.net/quote/quote

.EXAMPLE
  .\deploy_simple.ps1
  .\deploy_simple.ps1 -BaseName "myquickquote" -Location "eastus"
#>

param(
    [string]$ResourceGroup = "rg-quickquote-simple",
    [string]$Location = "eastus",
    [string]$BaseName = "",          # leave blank to auto-generate a unique name
    [string]$PublisherEmail = "admin@example.com"
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

if (-not $BaseName) {
    $BaseName = "qq" + (Get-Date -Format "MMddHHmm").ToLower()
}

$StorageName = ($BaseName + "stg").Replace("-", "").Substring(0, [Math]::Min(24, ($BaseName + "stg").Replace("-", "").Length))
if ($StorageName.Length -lt 3) { $StorageName = "qqstg" + (Get-Random -Maximum 9999) }
$FunctionName = "$BaseName-func"
$ApimName = "$BaseName-apim"
$ApiId = "quickquote-api"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Quick Quote - Simple APIM Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resource Group : $ResourceGroup"
Write-Host "Location       : $Location"
Write-Host "Function App   : $FunctionName"
Write-Host "APIM           : $ApimName"
Write-Host ""

Write-Host "[1/6] Checking Azure login..." -ForegroundColor Yellow
az account show -o none

Write-Host "[2/6] Creating resource group..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location -o none

function Test-AzResource {
    param([scriptblock]$Command)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $Command 2>$null | Out-Null
    $ok = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prev
    return $ok
}

Write-Host "[3/6] Creating storage account and Function App (consumption plan)..." -ForegroundColor Yellow
if (-not (Test-AzResource { az storage account show --name $StorageName --resource-group $ResourceGroup -o none })) {
    az storage account create `
        --name $StorageName `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --allow-blob-public-access false `
        -o none
}

if (-not (Test-AzResource { az functionapp show --name $FunctionName --resource-group $ResourceGroup -o none })) {
    az functionapp create `
        --name $FunctionName `
        --resource-group $ResourceGroup `
        --storage-account $StorageName `
        --consumption-plan-location $Location `
        --runtime python `
        --runtime-version 3.11 `
        --functions-version 4 `
        --os-type Linux `
        -o none
}

Write-Host "[4/6] Deploying Python code..." -ForegroundColor Yellow
$zipPath = Join-Path $env:TEMP "quickquote-deploy.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
$deployDir = Join-Path $env:TEMP "quickquote-deploy"
if (Test-Path $deployDir) { Remove-Item $deployDir -Recurse -Force }
New-Item -ItemType Directory -Path $deployDir | Out-Null
Copy-Item "function_app.py", "host.json", "index.html", "requirements.txt" -Destination $deployDir
Compress-Archive -Path "$deployDir\*" -DestinationPath $zipPath -Force
az functionapp deployment source config-zip `
    --resource-group $ResourceGroup `
    --name $FunctionName `
    --src $zipPath `
    -o none
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item $deployDir -Recurse -Force -ErrorAction SilentlyContinue

$FunctionUrl = "https://$FunctionName.azurewebsites.net"
Write-Host "       Function live at: $FunctionUrl/api/quote" -ForegroundColor Green

Write-Host "[5/6] Creating APIM (Consumption) - takes 5-10 minutes..." -ForegroundColor Yellow
if (-not (Test-AzResource { az apim show --name $ApimName --resource-group $ResourceGroup -o none })) {
    az apim create `
        --name $ApimName `
        --resource-group $ResourceGroup `
        --location $Location `
        --publisher-email $PublisherEmail `
        --publisher-name "Quick Quote" `
        --sku-name Consumption `
        -o none
}

Write-Host "[6/6] Configuring APIM API..." -ForegroundColor Yellow
if (-not (Test-AzResource { az apim api show --service-name $ApimName --resource-group $ResourceGroup --api-id $ApiId -o none })) {
    az apim api create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --path "quote" `
        --display-name "Quick Quote Travel Insurance" `
        --service-url "$FunctionUrl/api" `
        --protocols https `
        --subscription-required false `
        -o none

    az apim api operation create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --operation-id "get-quote" `
        --display-name "Get Travel Insurance Quote" `
        --method POST `
        --url-template "/quote" `
        -o none

    az apim api operation create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --operation-id "quote-ui" `
        --display-name "Quote Web UI" `
        --method GET `
        --url-template "/ui" `
        -o none

    az apim api operation create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --operation-id "openapi-spec" `
        --display-name "OpenAPI Schema for ChatGPT" `
        --method GET `
        --url-template "/openapi.json" `
        -o none
} else {
    az apim api update `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --path "quote" `
        --service-url "$FunctionUrl/api" `
        -o none
}

if (-not (Test-AzResource { az apim api operation show --service-name $ApimName --resource-group $ResourceGroup --api-id $ApiId --operation-id "quote-ui" -o none })) {
    az apim api operation create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --operation-id "quote-ui" `
        --display-name "Quote Web UI" `
        --method GET `
        --url-template "/ui" `
        -o none
}

if (-not (Test-AzResource { az apim api operation show --service-name $ApimName --resource-group $ResourceGroup --api-id $ApiId --operation-id "openapi-spec" -o none })) {
    az apim api operation create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --api-id $ApiId `
        --operation-id "openapi-spec" `
        --display-name "OpenAPI Schema for ChatGPT" `
        --method GET `
        --url-template "/openapi.json" `
        -o none
}

if (-not (Test-AzResource { az apim product show --service-name $ApimName --resource-group $ResourceGroup --product-id "unlimited" -o none })) {
    az apim product create `
        --service-name $ApimName `
        --resource-group $ResourceGroup `
        --product-id "unlimited" `
        --product-name "Unlimited" `
        --description "Open access for testing" `
        --subscription-required false `
        -o none
}

az apim product api add `
    --service-name $ApimName `
    --resource-group $ResourceGroup `
    --product-id "unlimited" `
    --api-id $ApiId `
    -o none 2>$null

Write-Host "       Waiting 30s for APIM gateway to pick up the API..." -ForegroundColor Gray
Start-Sleep -Seconds 30

$ApimUiUrl = "https://$ApimName.azure-api.net/quote/ui"
$ApimUrl = "https://$ApimName.azure-api.net/quote/quote"
$OpenApiUrl = "https://$ApimName.azure-api.net/quote/openapi.json"
$testBody = '{"destination":"Japan","age":35,"duration_days":10,"coverage_level":"Standard"}'

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " DEPLOYMENT COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Open in your browser (Web UI):" -ForegroundColor White
Write-Host "  $ApimUiUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "API endpoint (POST JSON):" -ForegroundColor White
Write-Host "  $ApimUrl" -ForegroundColor Cyan
Write-Host ""
Write-Host "ChatGPT Actions schema (import this URL):" -ForegroundColor White
Write-Host "  $OpenApiUrl" -ForegroundColor Cyan
Write-Host "  Run: .\setup_chatgpt.ps1 -ApimName $ApimName" -ForegroundColor Gray
Write-Host ""
Write-Host "Test with PowerShell:" -ForegroundColor White
Write-Host "  Invoke-RestMethod -Uri '$ApimUrl' -Method POST -ContentType 'application/json' -Body '$testBody'" -ForegroundColor Gray
Write-Host ""
Write-Host "Direct Function URL (bypass APIM):" -ForegroundColor White
Write-Host "  $FunctionUrl/api/quote" -ForegroundColor Gray
Write-Host ""
