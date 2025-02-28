# ARO Store Demo

## Create ARO cluster

Refer to the ARO docs.

Just create a default cluster with public API Server and Console.

## Deploy AKS app to create the necessary Azure infrastrcuture

```sh
azd up
```

## Deploy ARO application

```sh
cd aro-demo/
source ./aro-env.sh
az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER

az aro show \
    --name $CLUSTER \
    --resource-group $RESOURCEGROUP \
    --query "consoleProfile.url" -o tsv

ARO_API_URI="$(az aro show --name $CLUSTER --resource-group $RESOURCEGROUP --query "apiserverProfile.url" -o tsv)"
ARO_PASSWORD="$(az aro list-credentials -g $RESOURCEGROUP -n $CLUSTER | jq -r ".kubeadminPassword")"
oc login $ARO_API_URI -u kubeadmin -p $ARO_PASSWORD
oc status

cp ../custom-values.yaml .

# Allow less secure configuration for store-front, store-admin, ai-service
oc adm policy add-scc-to-user anyuid -z default -n pet

# Ensure custom-values.yaml has as we don't want to use load balancer services, we'll use OpenShift Routes:
# storeAdmin:
#   serviceType: ClusterIP
# storeFront:
#   serviceType: ClusterIP

AZD_RG=$(azd env get-value AZURE_RESOURCE_GROUP)
AZD_SUB_ID=$(azd env get-value AZURE_SUBSCRIPTION_ID)
AZD_AOAI_NAME=$(azd env get-value AZURE_OPENAI_ENDPOINT | cut -d'/' -f3 | cut -d'.' -f1)
AZURE_SERVICE_BUS_NAMESPACE=$(azd env get-value AZURE_SERVICE_BUS_HOST | cut -d'/' -f3 | cut -d'.' -f1)
AZD_COSMOSDB_ACCOUNT=$(azd env get-value AZURE_COSMOS_DATABASE_NAME)

az ad sp create-for-rbac --name aro-demo-aoai-sp --role "Cognitive Services OpenAI User" --scopes /subscriptions/$AZD_SUB_ID/resourceGroups/$AZD_RG/providers/Microsoft.CognitiveServices/accounts/$AZD_AOAI_NAME > ./aoai-sp.json

SP_CLIENT_ID=$(jq -r .appId < ./aoai-sp.json)

SERVICE_BUS_NAMESPACE_ID=$(az servicebus namespace show -g $AZD_RG -n $AZURE_SERVICE_BUS_NAMESPACE --query id -o tsv)
az role assignment create --assignee $SP_CLIENT_ID --role "Azure Service Bus Data Owner" --scope $SERVICE_BUS_NAMESPACE_ID

COSMOSDB_ACCOUNT_ID=$(az cosmosdb show --resource-group $AZD_RG --name $AZD_COSMOSDB_ACCOUNT --query id -o tsv)
COSMOSDB_ROLE_ID=$(az cosmosdb sql role definition list --resource-group $AZD_RG --account-name $AZD_COSMOSDB_ACCOUNT | jq -r '.[] | select(.roleName == "Cosmos DB Built-in Data Contributor") | .id')

PRINCIPAL_ID=$(az ad sp list --filter "appId eq '$SP_CLIENT_ID'" --query "[0].id" -o tsv)

az cosmosdb sql role assignment create --resource-group $AZD_RG --account-name $AZD_COSMOSDB_ACCOUNT --role-definition-id $COSMOSDB_ROLE_ID --principal-id $PRINCIPAL_ID --scope $COSMOSDB_ACCOUNT_ID
az cosmosdb sql role assignment create --resource-group $AZD_RG --account-name $AZD_COSMOSDB_ACCOUNT --role-definition-id $COSMOSDB_ROLE_ID --principal-id $(az ad signed-in-user show --query id -o tsv) --scope $COSMOSDB_ACCOUNT_ID
az cosmosdb sql role assignment list --resource-group $AZD_RG --account-name $AZD_COSMOSDB_ACCOUNT

# AI service cannot use managed identity on ARO yet
# Update custom-values.yaml
# aro: true
# azure:
#   clientId: <tenantId-from-sp>
#   tenantId: <tenantId-from-sp>
#   clientSecret: <secret-from-sp>
helm upgrade demo ../charts/aks-store-demo --install --wait --version 1.2.0 --values ./custom-values.yaml --namespace pets --create-namespace

# Create a TLS edge route
oc create route edge store-front --service=store-front
oc create route edge store-admin --service=store-admin
oc get route store-front
oc get route store-admin
```

Update the Azure Cosmos DB account networking to accept 0.0.0.0 (connections from Azure datacenter public IPs).  Or just set it to enable all access.
Otherwise, makeline service can't post the order to it.

## Setup Service Mesh

From the OperatorHub in ARO, install these Red Hat supported operators:

* Red Hat OpenShift Service Mesh 2
* Kiali
* Tempo

### Configure mesh components

```sh
oc apply -f manifests/kiali-role.yaml
oc apply -f manifests/kiali-role-binding.yaml
oc apply -f manifests/servicemeshcontrolplane.yaml
```

### Onboard app to the mesh

```sh
oc apply -f manifests/pets-servicemesh-member.yaml

TLS_SECRET_NAME=$(oc get deployment/router-default -o yaml -n openshift-ingress -o json | jq -r .spec.template.spec.volumes[0].secret.secretName)
oc get secret $TLS_SECRET_NAME -n openshift-ingress -o yaml > manifests/tls-secret.yaml
# Modify secret:

# metadata:
#   creationTimestamp: "2025-02-27T04:40:52Z"
#   name: a6c13d9c-ea03-4075-867a-87dc517fb9e2-ingress
#   namespace: openshift-ingress
#   resourceVersion: "55961"
#   uid: 7f00a96a-c0a7-4f88-ab8d-33f758cee25d

# to:

# metadata:
#   name: demo-ingress-tls
#   namespace: pets

oc apply -f manifests/tls-secret.yaml

# Update domains in manifests/gateways-istio.yaml and manifests/routes-istio.yaml
oc apply -f manifests/gateways-istio.yaml

# If not using auto route generation uncomment line below:
# oc apply -f manifests/routes-istio.yaml

# If using auto route generation then edit the two routes for store-admin and store-front and add:

# spec:
#   tls:
#     insecureEdgeTerminationPolicy: Redirect
#     termination: edge

oc get pod
oc get deployment -o name | xargs -I {} oc rollout restart {}
oc get pod
```
