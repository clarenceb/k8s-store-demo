# ARO Store Demo

Adaptation of the [AKS Store Demo](github.com:Azure-Samples/aks-store-demo) for Azure Red Hat OpenShift (ARO) with Istio service mesh and Kiali for mesh observability.

## Create ARO cluster

Refer to the ARO docs for how to [create your cluster](https://learn.microsoft.com/en-us/azure/openshift/create-cluster).

For this demo, just create a default ARO cluster with a public API Server and ingress.

## Deploy the AKS infra to create the necessary Azure infrastrcuture

To save time, we'll use the existing setup from the AKS Store Demo to get an environment up and running using the Azure Developer CLI.
You can stop the AKS cluster or delete it afterwards.

```sh
cd ..
azd up
```

## Deploy the Pet Store application to ARO

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

cp ../custom-values.yaml ./custom-values.yaml

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
# oc create route edge store-front --service=store-front
# oc create route edge store-admin --service=store-admin
oc apply -f aro-demo/manifests/routes-istio.yaml
oc get route -n istio-system

# IP whitelist your client ip since these are public endpoints
MY_CLIENT_IP=$(curl ifconfig.me)
oc annotate route pets-store-front-gw-17ece1ccbd2b8ae0 haproxy.router.openshift.io/ip_whitelist="${MY_CLIENT_IP}" -n istio-system
oc annotate route pets-store-admin-gw-adbfdae3e2393f1e haproxy.router.openshift.io/ip_whitelist="${MY_CLIENT_IP}" -n istio-system

oc describe route pets-store-front-gw-17ece1ccbd2b8ae0 -n istio-system
oc describe route pets-store-admin-gw-adbfdae3e2393f1e -n istio-system
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

# Verify outboundTrafficPolicy is REGISTRY_ONLY to block egress traffic not listed in ServiceEntry objects
oc get cm/istio-basic -n istio-system -o yaml | grep -o "mode: REGISTRY_ONLY" | uniq
oc get cm/istio-sidecar-injector-basic -n istio-system -o yaml | grep -o "REGISTRY_ONLY" | uniq
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

# Strict mTLS in cluster
oc patch peerauthentication default -n istio-system --type='merge' -p '{"spec":{"mtls":{"mode":"STRICT"}}}'
oc describe peerauthentication default -n istio-system

# Create service entries
oc apply -f manifests/service-entries.yaml

# Apply authorization policies
oc apply -f manifests/authz-policies.yaml

oc get pod
oc get deployment -o name | xargs -I {} oc rollout restart {}
oc get pod
```
