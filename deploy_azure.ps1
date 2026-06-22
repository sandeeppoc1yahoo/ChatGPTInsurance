<#
.SYNOPSIS
Deploys the Quick Quote MCP application to Azure Container Apps and configures APIM.

.DESCRIPTION
This script will:
1. Create a Resource Group.
2. Build and deploy the Docker image to Azure Container Apps.
3. Provision an Azure API Management (Consumption tier) instance.
4. Link the Container App to APIM and apply the MCP Gateway XML policy.
#>

# --- CONFIGURATION VARIABLES ---
# TODO: Fill these in before running!
$SubscriptionId = "8aac3efc-875f-46d9-9fdc-99c8911f6919"
$ResourceGroupName = "rg-quickquote-mcp-demo"
$Location = "eastus"
$BaseName = "quickquotemcp0621" # Must be unique globally (no spaces, all lowercase)

# Derived names
$ContainerAppName = "$BaseName-app"
$ApimName = "$BaseName-apim"
$PublisherEmail = "admin@example.com"
$PublisherName = "Quick Quote Admin"

# --- LOGIN & SETUP ---
Write-Host "Ensuring Azure login..."
# az login
az account set --subscription $SubscriptionId

# --- RESOURCE GROUP ---
Write-Host "Creating Resource Group: $ResourceGroupName in $Location..."
az group create --name $ResourceGroupName --location $Location

# --- DEPLOY CONTAINER APP ---
Write-Host "Deploying Docker container to Azure Container Apps ($ContainerAppName)..."
# The 'az containerapp up' command builds the local Dockerfile and deploys it.
# We map the internal port 8000 to the container app's ingress.
az containerapp up `
    --name $ContainerAppName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --source . `
    --ingress external `
    --target-port 8000 `
    --env-vars "PYTHONUNBUFFERED=1"

# Get the Container App FQDN
$AppFqdn = az containerapp show --name $ContainerAppName --resource-group $ResourceGroupName --query properties.configuration.ingress.fqdn -o tsv
$AppUrl = "https://$AppFqdn"
Write-Host "Container App deployed at: $AppUrl"

# --- DEPLOY API MANAGEMENT ---
Write-Host "Provisioning API Management (Consumption tier) - This takes ~5 minutes..."
az apim create `
    --name $ApimName `
    --resource-group $ResourceGroupName `
    --location $Location `
    --publisher-email $PublisherEmail `
    --publisher-name $PublisherName `
    --sku-name Consumption

# --- CONFIGURE APIM API ---
Write-Host "Configuring APIM API for MCP Gateway..."
$ApiId = "mcp-gateway"
az apim api create `
    --service-name $ApimName `
    --resource-group $ResourceGroupName `
    --api-id $ApiId `
    --path "/mcp" `
    --display-name "MCP Gateway API" `
    --service-url $AppUrl `
    --protocols https

# Create the specific operations
Write-Host "Creating GET /sse operation..."
az apim api operation create `
    --service-name $ApimName `
    --resource-group $ResourceGroupName `
    --api-id $ApiId `
    --operation-id "mcp-sse" `
    --display-name "MCP SSE Connection" `
    --method GET `
    --url-template "/sse"

Write-Host "Creating POST /messages operation..."
az apim api operation create `
    --service-name $ApimName `
    --resource-group $ResourceGroupName `
    --api-id $ApiId `
    --operation-id "mcp-messages" `
    --display-name "MCP Messages" `
    --method POST `
    --url-template "/messages"

# --- APPLY POLICIES ---
Write-Host "Applying MCP Gateway Policy to the APIM API..."
# First, read the policy file and replace the placeholder URL with the actual Container App URL
$PolicyContent = Get-Content .\apim_policy_mcp_gateway.xml -Raw
$PolicyContent = $PolicyContent -replace "<YOUR_CONTAINER_APP_URL>", $AppUrl
$PolicyTempFile = ".\apim_policy_temp.xml"
$PolicyContent | Set-Content $PolicyTempFile

# Apply policy
az apim api policy create `
    --service-name $ApimName `
    --resource-group $ResourceGroupName `
    --api-id $ApiId `
    --value-path $PolicyTempFile

# Cleanup temp file
Remove-Item $PolicyTempFile

$ApimUrl = "https://$ApimName.azure-api.net/mcp/sse"
Write-Host "======================================================="
Write-Host "DEPLOYMENT COMPLETE!"
Write-Host "Your APIM MCP Gateway is live at: $ApimUrl"
Write-Host "======================================================="
