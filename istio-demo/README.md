# AKS Istio Demo - Pet Store

For general AKS Istio add-on and observability components setup see: https://github.com/clarenceb/aks-istio-demo

## Pre-requisites

- AKS Cluster with `pets` namespace and app deployed via `azd up`
- [Istio add-on enabled](https://learn.microsoft.com/en-us/azure/aks/istio-deploy-addon#install-istio-add-on)
- Prometheus, Grafana, Kiali installed in the cluster `aks-istio-system` namespace

```sh
# Prometheus - metrics
curl -s https://raw.githubusercontent.com/istio/istio/release-${ISTIO_RELEASE}/samples/addons/prometheus.yaml | sed 's/istio-system/aks-istio-system/g' | kubectl apply -f -

# Grafana - monitoring and metrics dashboards
curl -s https://raw.githubusercontent.com/istio/istio/release-${ISTIO_RELEASE}/samples/addons/grafana.yaml | sed 's/istio-system/aks-istio-system/g' | kubectl apply -f -

# Jaeger - distributed tracing
curl -s https://raw.githubusercontent.com/istio/istio/release-${ISTIO_RELEASE}/samples/addons/jaeger.yaml | sed 's/istio-system/aks-istio-system/g' | kubectl apply -f -

# Kiali installation
helm repo add kiali https://kiali.org/helm-charts
helm repo update

helm install \
    --set cr.create=true \
    --set cr.namespace=aks-istio-system \
    --namespace aks-istio-system \
    --create-namespace \
    kiali-operator \
    kiali/kiali-operator

# Generate a short-lived token to login to Kiali UI
kubectl -n aks-istio-system create token kiali-service-account

# Port forward to Istio service to access on http://localhost:20001
kubectl port-forward svc/kiali 20001:20001 -n aks-istio-system
```

- (Optional) Secure (TLS) Istio Ingress Gateway configuration (otherwise, just use HTTP with the ingress public IP address)

## Add user node pool and set taints on system node pool

```sh
az aks nodepool add --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER --name apps --max-pods 30 --min-count 1 --max-count 3 --mode User --os-type Linux --os-sku Ubuntu --zones "1 2 3" --node-vm-size Standard_D4pds_v6
az aks nodepool update --node-taints CriticalAddonsOnly=true:NoSchedule --resource-group $RESOURCE_GROUP --cluster-name $CLUSTER --name system
```

## Re-deploy the heml chart with overrides

```sh
cp ../custom-values.yaml ./custom-values.yaml
# Update the generated `custom-values.yaml` file with these values:
# aro: false
# useMesh: false
# storeAdmin:
#   serviceType: ClusterIP
# storeFront:
#   serviceType: ClusterIP

cd istio-demo/
helm upgrade demo ../charts/aks-store-demo --install --wait --version 1.2.0 --values ./custom-values.yaml --namespace pets --create-namespace
```

## Enable strict mTLS in cluster

```sh
kubectl apply -f istio-demo/manifests/peer-authentication.yaml
```

## Configure outbound policy to REGISTRY_ONLY

Block all egress from the cluster without service entries.

```sh
kubectl apply  -f istio-demo/manifests/istio-shared-configmap-asm-1-23.yaml

# Kiali might need a restart to pick up service entries
kubectl rollout restart deployment kiali -n kiali
```

# Create service entries

```sh
kubectl apply -f istio-demo/manifests/service-entries.yaml -n pets
```

# Apply authorization policies

```sh
kubectl apply -f istio-demo/manifests/authz-policies.yaml
```

## Onboard the pets namespace to the mesh

```sh
echo "Istio revision: ${REVISION?:"Missing istio revision, please set it first."}"
kubectl label namespace pets istio.io/rev=${REVISION}
```

## Restart the pets deployents

```sh
kubectl get pod -n pets
kubectl get deployment -o name -n pets | xargs -I {} kubectl rollout restart {} -n pets
kubectl get pod -n pets
```

## (Optional) Create Gateway and Virtual Service

If using a TLS Ingress setup:

```sh
kubectl apply -f istio-demo/manifests/gateways-istio.yaml
kubectl get gateway,virtualservice -n pets
```

## Get the ingress endpoints and test the app

```sh
kubectl get gateway store-front-gw -n pets 2>&1 > /dev/null
if [[ $? == 0 ]]; then
    STORE_FRONT_URL="https://$(kubectl get gateway store-front-gw -n pets -o jsonpath='{.spec.servers[0].hosts[0]}')"
    STORE_ADMIN_URL="https://$(kubectl get gateway store-admin-gw -n pets -o jsonpath='{.spec.servers[0].hosts[1]}')"
else
    STORE_FRONT_URL="http://$(kubectl get service -n pets store-front -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"
    STORE_ADMIN_URL="http://$(kubectl get service -n pets store-admin -o jsonpath='{.status.loadBalancer.ingress[0].ip})"
fi

echo "STORE_FRONT_URL=$STORE_FRONT_URL"
echo "STORE_ADMIN_URL=$STORE_ADMIN_URL"
```

You can also just port-forward if you didn't use TLS on the ingress or you didn't use LoadBalancer type on the external services.

```sh
kubectl port-forward -n pets store-front 8080:80 &
kubectl port-forward -n pets store-admin 8081:80 &
```

Test that the app is meshed and is working.

## Resources

* [Configure Istio-based service mesh add-on for Azure Kubernetes Service](https://learn.microsoft.com/en-us/azure/aks/istio-meshconfig)
