# set the main deployment location
azd env set AZURE_LOCATION australiaeast 

# set the SKU of the virtual machine scale set nodes in the AKS cluster
azd env set AKS_VMSS_SKU Standard_DS2_v3

# deploys azure container registry and builds containers from source
azd env set DEPLOY_AZURE_CONTAINER_REGISTRY false 

# builds containers from source using the az acr build command otherwise imports containers from the github container registry
azd env set BUILD_CONTAINERS false 

# enables workload identity on the aks cluster and deploys managed identities
azd env set DEPLOY_AZURE_WORKLOAD_IDENTITY true

# deploys azure openai
azd env set DEPLOY_AZURE_OPENAI true

# azure openai region
azd env set AZURE_OPENAI_LOCATION australiaeast 

# deploys the DALL-E 3 model on azure openai
azd env set DEPLOY_AZURE_OPENAI_DALL_E_MODEL true

# deploys azure service bus
azd env set DEPLOY_AZURE_SERVICE_BUS true

# deploys azure cosmos db with the sql api
azd env set DEPLOY_AZURE_COSMOSDB true

# choose the appropriate region pair for your preferred location
azd env set AZURE_COSMOSDB_FAILOVER_LOCATION australiasoutheast 

# note this is the default when DEPLOY_AZURE_WORKLOAD_IDENTITY is set to true
azd env set AZURE_COSMOSDB_ACCOUNT_KIND GlobalDocumentDB

# deploys aks observability tools
azd env set DEPLOY_OBSERVABILITY_TOOLS true
