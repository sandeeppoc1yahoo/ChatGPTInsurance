@echo off
:: Automatically change directory to where this script is located
cd /d "%~dp0"

echo =======================================================
echo Deploying the Quick Quote MCP application to Azure...
echo =======================================================

:: --- CONFIGURATION VARIABLES ---
set ResourceGroupName=rg-quickquote-mcp-demo
set Location=canadacentral
set BaseName=quickquotemcp0622

:: Derived names
set ContainerAppName=%BaseName%-app
set ApimName=%BaseName%-apim

echo.
echo [1/4] Using your Default Azure Subscription...
:: We removed the hardcoded subscription ID. Azure will automatically use whichever account is logged in!

echo Registering Microsoft.App provider (can take a minute if not already registered)...
call az provider register -n Microsoft.App

echo.
echo [2/4] Creating Resource Group: %ResourceGroupName% in %Location%...
call az group create --name "%ResourceGroupName%" --location "%Location%"

echo.
echo [3/4] Deploying Docker container to Azure Container Apps...
call az containerapp up ^
    --name "%ContainerAppName%" ^
    --resource-group "%ResourceGroupName%" ^
    --location "%Location%" ^
    --source . ^
    --ingress external ^
    --target-port 8000 ^
    --env-vars "PYTHONUNBUFFERED=1"

:: Get the FQDN
echo Retrieving Container App FQDN...
FOR /F "tokens=*" %%g IN ('az containerapp show --name "%ContainerAppName%" --resource-group "%ResourceGroupName%" --query properties.configuration.ingress.fqdn -o tsv') do (SET AppFqdn=%%g)
set AppUrl=https://%AppFqdn%
echo Container App deployed at: %AppUrl%

echo.
echo [4/4] Provisioning API Management (Consumption tier)...
echo This step can take 5-10 minutes. Please wait...
call az apim create ^
    --name "%ApimName%" ^
    --resource-group "%ResourceGroupName%" ^
    --location "%Location%" ^
    --publisher-email "admin@example.com" ^
    --publisher-name "Quick Quote Admin" ^
    --sku-name Consumption

echo.
echo Configuring APIM API for MCP Gateway...
set ApiId=mcp-gateway
call az apim api create ^
    --service-name "%ApimName%" ^
    --resource-group "%ResourceGroupName%" ^
    --api-id "%ApiId%" ^
    --path "/mcp" ^
    --display-name "MCP Gateway API" ^
    --service-url "%AppUrl%" ^
    --protocols https

echo Creating GET /sse operation...
call az apim api operation create ^
    --service-name "%ApimName%" ^
    --resource-group "%ResourceGroupName%" ^
    --api-id "%ApiId%" ^
    --operation-id "mcp-sse" ^
    --display-name "MCP SSE Connection" ^
    --method GET ^
    --url-template "/sse"

echo Creating POST /messages operation...
call az apim api operation create ^
    --service-name "%ApimName%" ^
    --resource-group "%ResourceGroupName%" ^
    --api-id "%ApiId%" ^
    --operation-id "mcp-messages" ^
    --display-name "MCP Messages" ^
    --method POST ^
    --url-template "/messages"

echo.
echo Applying MCP Gateway Policy...
:: Read XML, replace URL, and write to temp file using PowerShell
powershell -Command "(Get-Content 'apim_policy_mcp_gateway.xml') -replace '<YOUR_CONTAINER_APP_URL>', '%AppUrl%' | Set-Content 'apim_policy_temp.xml'"

call az apim api policy create ^
    --service-name "%ApimName%" ^
    --resource-group "%ResourceGroupName%" ^
    --api-id "%ApiId%" ^
    --value-path "apim_policy_temp.xml"

del apim_policy_temp.xml

echo =======================================================
echo DEPLOYMENT COMPLETE!
echo Your APIM MCP Gateway is live at: https://%ApimName%.azure-api.net/mcp/sse
echo =======================================================
