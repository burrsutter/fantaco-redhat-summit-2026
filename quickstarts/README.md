# How to configure the workshop cluster to support the RAG Quickstart


## Prerequisites

* Know your MaaS URL and API key
* Must be Cluster Admin
* The RAG Quickstart uses RHOAI Pipelines, those will be enabled below


Look for the following but "filled in" within the demo cluster.

## Steps

```bash
curl -sS {litellm_api_base_url}/models   -H "Authorization: Bearer {litellm_virtual_key}" | jq
```

![MaaS Details](images/MaaS_details.png)


```bash
git clone https://github.com/rh-ai-quickstart/RAG
```

OR 


```bash
git clone --branch v0.2.30 https://github.com/rh-ai-quickstart/RAG.git
```

## Enable Pipelines

Login as Cluster Admin

```bash
oc login ...
```

![Login](images/login_1.png)

![Login](images/login_2.png)


Find the DataScienceCluster


```bash
oc get dsc
```

There is one per namespace

```bash
NAME          READY   REASON
default-dsc   True
```

By default the workshop clusters have AI Pipelines disabled (aka "Removed")

```bash
echo "aipipelines: $(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.aipipelines.managementState}')"
```

```
aipipelines: Removed
```

Patch to enable (aka "Managed")


```bash
oc patch datasciencecluster default-dsc --type='json' -p '[{"op":"replace","path":"/spec/components/aipipelines/managementState","value":"Managed"}]'
```

```
datasciencecluster.datasciencecluster.opendatahub.io/default-dsc patched
```

```bash
echo "aipipelines: $(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.aipipelines.managementState}')"
```

```
aipipelines: Managed
```

Also verify the `argoWorkflowsControllers`

```bash
echo "argoWorkflowsControllers: $(oc get datasciencecluster default-dsc -o jsonpath='{.spec.components.aipipelines.argoWorkflowsControllers.managementState}')"
```

```
argoWorkflowsControllers: Removed
```

And patch the `argoWorkflowsControllers`

```bash
oc patch datasciencecluster default-dsc --type='merge' -p '{"spec":{"components":{"aipipelines":{"managementState":"Managed","argoWorkflowsControllers":{"managementState":"Managed"}}}}}'
```

```
argoWorkflowsControllers: Managed
```

CRDs

```bash
oc get crd | grep datasciencepipelines
```

```
datasciencepipelines.components.platform.opendatahub.io                            2026-01-14T21:58:32Z
datasciencepipelinesapplications.datasciencepipelinesapplications.opendatahub.io   2026-01-14T23:22:23Z
```

And a new pod

```bash
oc get pods -n redhat-ods-applications
```

```
NAME                                                              READY   STATUS      RESTARTS   AGE
data-science-pipelines-operator-controller-manager-5cbcdc875jsg   1/1     Running     0          2m10s
kserve-controller-manager-64b497ccdd-rfkw9                        1/1     Running     0          84m
llama-stack-k8s-operator-controller-manager-5b9b945794-7f5d6      1/1     Running     0          84m
notebook-controller-deployment-6697968bbf-f7m4f                   1/1     Running     0          84m
odh-model-controller-64c489b874-mt9k2                             1/1     Running     0          84m
odh-notebook-controller-manager-6c65f4d46f-bk6rw                  1/1     Running     0          84m
rhoai-patcher-dashboard-9l4rx                                     0/1     Completed   0          84m
rhoai-patcher-dashboard-pp4zg                                     0/1     Error       0          84m
rhoai-patcher-route-6lhdh                                         0/1     Completed   0          84m
rhods-dashboard-6c8744b89-spd9n                                   4/4     Running     0          84m
```


or the GUI way

![RHOAI DSC](images/RHOAI_DSC_1.png)

![RHOAI DSC](images/RHOAI_DSC_2.png)

![RHOAI DSC](images/RHOAI_DSC_3.png)

![RHOAI DSC](images/RHOAI_DSC_4.png)


## RHOAI Console


![RHOAI Console](images/RHOAI_Console_1.png)

OR 

```bash
oc get consolelinks rhodslink
```

Look for the Pipelines menu option

![RHOAI Console](images/RHOAI_Console_2.png)


## Edit the configuration

```bash
cd deploy/helm
```

```bash
cp rag-values.yaml.example rag-values.yaml
```

![RAG Quickstart directory](images/RAG_Quickstart_1.png)


Edit rag-values.yaml 

```bash
    remote-llm:
      id: vllm/qwen3-14b
      url:  https://litellm-prod.apps.maas.redhatworkshops.io/v1
      apiToken: sk-8SekoVW7apOY1rS3k
      enabled: true

    remote-llm:  
      id: vllm/llama-scout-17b
      url:  https://litellm-prod.apps.maas.redhatworkshops.io/v1
      apiToken: sk-8SekoVW7apOY1rS3k
      enabled: true

    remote-llm:  
      id: Llama-Guard-3-1B
      url:  https://litellm-prod.apps.maas.redhatworkshops.io/v1
      apiToken: sk-8SekoVW7apOY1rS3k
      enabled: true

```

== Install

```bash
make install NAMESPACE=rag-quickstart
```

Since we are using the MaaS, the Huggingface token is optional


```
Enter your Hugging Face token (or press Enter to skip):
```

**Press Enter**


```
Enter your TAVILY search API key (or press Enter to skip):
```

The Tavily key is also optional.  If you have one, provide it as that enables the Web Search capability


```bash
watch oc get pods
```

```
NAME                                                    READY   STATUS              RESTARTS   AGE
add-hr-pipeline-pipeline-2ltnw                          0/1     Init:0/1            0          89s
add-legal-pipeline-pipeline-fhwrn                       0/1     Init:0/1            0          89s
add-procurement-pipeline-pipeline-lbp5r                 0/1     Init:0/1            0          89s
add-sales-pipeline-pipeline-5j44p                       0/1     Init:0/1            0          89s
add-techsupport-pipeline-pipeline-whk94                 0/1     Init:0/1            0          89s
ds-pipeline-dspa-684ff947bb-qb2bw                       1/2     Running             0          14s
ds-pipeline-metadata-envoy-dspa-8d7fc97b-2hdw2          0/2     Running             0          11s
ds-pipeline-metadata-grpc-dspa-bf5499fff-c76vw          0/1     ContainerCreating   0          10s
ds-pipeline-persistenceagent-dspa-86dc9b4f44-tsl7g      0/1     ContainerCreating   0          14s
ds-pipeline-scheduledworkflow-dspa-76684865cf-7z9pz     0/1     ContainerCreating   0          14s
ds-pipeline-workflow-controller-dspa-57968bf8f5-24t2k   1/1     Running             0          13s
llamastack-59ddd96b7c-tfm8m                             1/1     Running             0          89s
mariadb-dspa-5bf448b956-pkzzg                           1/1     Running             0          88s
mcp-weather-6fc69bc978-d76th                            1/1     Running             0          89s
minio-0                                                 1/1     Running             0          89s
pgvector-0                                              1/1     Running             0          89s
rag-66b4f66fcb-v7lf7                                    1/1     Running             0          89s
rag-ingestion-pipeline-55599bcc98-kfc8c                 0/1     Init:0/1            0          89s
rag-pipeline-notebook-0                                 1/1     Running             0          88s
upload-sample-docs-job-2xdnj                            1/1     Running             0          89s
```

Look at the Llama Stack pod specifically

```bash
oc get pod -l app.kubernetes.io/name=llamastack
```

```
NAME                          READY   STATUS    RESTARTS   AGE
llamastack-59ddd96b7c-tfm8m   1/1     Running   0          1m27s
```

And the RAG pod, the one with the application inside


```bash
oc get pods -l app.kubernetes.io/name=rag
```

```
NAME                   READY   STATUS    RESTARTS   AGE
rag-66b4f66fcb-v7lf7   1/1     Running   0          1m28s
```

Get the URL to the RAG GUI

```bash
export RAG_GUI=https://$(oc get routes -l app.kubernetes.io/name=rag -o jsonpath="{range .items[*]}{.status.ingress[0].host}{end}")
echo $RAG_GUI
```


![RAG GUI](images/RAG_GUI_1.png)

![RAG GUI](images/RAG_GUI_2.png)

Drag & Drop in a document

![New Vector DB](images/New_Vector_DB_DnD_1.png)

![New Vector DB](images/New_Vector_DB_DnD_2.png)

![New Vector DB](images/New_Vector_DB_DnD_3.png)

![New Vector DB](images/New_Vector_DB_DnD_4.png)


![RAG HR Benefits](images/RAG_HR_Benefits_1.png)


![RAG HR Benefits](images/RAG_HR_Benefits_2.png)

If you had provided your Tavily key, you can test the Web Search tool

![Tavily](images/tavily_key_1.png)

![Tavily](images/tavily_key_2.png)