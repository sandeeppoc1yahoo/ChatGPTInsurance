@echo off
cd /d "%~dp0"

set RG=rg-quickquote-mcp-demo
set LOC=canadacentral
set ACR=quickquotemcp0622acr
set ENV=quickquotemcp0622-env
set APP=quickquotemcp0622-app
set APIM=quickquotemcp0622-apim

echo Creating ACR...
call az acr create -n %ACR% -g %RG% --sku Basic --admin-enabled true

echo Building image in ACR...
call az acr build -r %ACR% -t quickquotemcp:latest .

echo Getting ACR credentials...
FOR /F "tokens=*" %%g IN ('az acr show -n %ACR% --query loginServer -o tsv') do (SET ACR_SERVER=%%g)
FOR /F "tokens=*" %%g IN ('az acr credential show -n %ACR% --query username -o tsv') do (SET ACR_USER=%%g)
FOR /F "tokens=*" %%g IN ('az acr credential show -n %ACR% --query "passwords[0].value" -o tsv') do (SET ACR_PASS=%%g)

echo Creating Container App Env...
call az containerapp env create -n %ENV% -g %RG% -l %LOC%

echo Creating Container App...
call az containerapp create -n %APP% -g %RG% --environment %ENV% --image "%ACR_SERVER%/quickquotemcp:latest" --target-port 8000 --ingress external --registry-server %ACR_SERVER% --registry-username %ACR_USER% --registry-password %ACR_PASS%

echo Retrieving App FQDN...
FOR /F "tokens=*" %%g IN ('az containerapp show --name %APP% --resource-group %RG% --query properties.configuration.ingress.fqdn -o tsv') do (SET AppFqdn=%%g)
set AppUrl=https://%AppFqdn%
echo App deployed at: %AppUrl%

echo Configuring APIM...
set ApiId=mcp-gateway
call az apim api create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --path "/mcp" --display-name "MCP Gateway API" --service-url "%AppUrl%" --protocols https
call az apim api operation create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --operation-id "mcp-sse" --display-name "MCP SSE Connection" --method GET --url-template "/sse"
call az apim api operation create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --operation-id "mcp-messages" --display-name "MCP Messages" --method POST --url-template "/messages"

echo Applying policy...
powershell -Command "(Get-Content 'apim_policy_mcp_gateway.xml') -replace '<YOUR_CONTAINER_APP_URL>', '%AppUrl%' | Set-Content 'apim_policy_temp.xml'"
call az apim api policy create --service-name "%APIM%" --resource-group "%RG%" --api-id "%ApiId%" --value-path "apim_policy_temp.xml"
del apim_policy_temp.xml

echo DONE! URL: https://%APIM%.azure-api.net/mcp/sse
