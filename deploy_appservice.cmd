@echo off
cd /d "%~dp0"

set RG=rg-quickquote-mcp-demo
set LOC=canadacentral
set PLAN=quickquotemcp0622-plan
set APP=quickquotemcp0622-app
set APIM=quickquotemcp0622-apim

echo [1/4] Creating App Service Plan (Linux/Python)...
call az appservice plan create --name "%PLAN%" --resource-group "%RG%" --location "%LOC%" --sku B1 --is-linux

echo [2/4] Creating Web App with Python 3.11...
call az webapp create --name "%APP%" --resource-group "%RG%" --plan "%PLAN%" --runtime "PYTHON:3.11"

echo [3/4] Deploying Python code via zip deploy...
powershell -Command "Compress-Archive -Path 'main_mcp_gateway.py','requirements.txt' -DestinationPath 'app.zip' -Force"
call az webapp deploy --name "%APP%" --resource-group "%RG%" --src-path "app.zip" --type zip

echo Setting startup command...
call az webapp config set --name "%APP%" --resource-group "%RG%" --startup-file "uvicorn main_mcp_gateway:app --host 0.0.0.0 --port 8000"

echo Retrieving App URL...
FOR /F "tokens=*" %%g IN ('az webapp show --name "%APP%" --resource-group "%RG%" --query defaultHostName -o tsv') do (SET AppFqdn=%%g)
set AppUrl=https://%AppFqdn%
echo App deployed at: %AppUrl%

echo [4/4] Configuring APIM API...
set ApiId=mcp-gateway
call az apim api create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --path "/mcp" --display-name "MCP Gateway API" --service-url "%AppUrl%" --protocols https

call az apim api operation create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --operation-id "mcp-sse" --display-name "MCP SSE Connection" --method GET --url-template "/sse"

call az apim api operation create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --operation-id "mcp-messages" --display-name "MCP Messages" --method POST --url-template "/messages"

echo Applying MCP Gateway Policy...
powershell -Command "(Get-Content 'apim_policy_mcp_gateway.xml') -replace '<YOUR_CONTAINER_APP_URL>', '%AppUrl%' | Set-Content 'apim_policy_temp.xml'"
call az apim api policy create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --value-path "apim_policy_temp.xml"
del apim_policy_temp.xml
del app.zip

echo =======================================================
echo DEPLOYMENT COMPLETE!
echo App URL: %AppUrl%
echo APIM MCP Gateway: https://%APIM%.azure-api.net/mcp/sse
echo =======================================================
