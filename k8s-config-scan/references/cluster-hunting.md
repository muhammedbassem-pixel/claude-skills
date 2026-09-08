# Hunting issues on a live Kubernetes cluster

Both tools below act on a **running cluster** — only run them where you are authorized.

## kube-bench — CIS Kubernetes Benchmark

kube-bench checks a cluster's **nodes** (kubelet/apiserver/etcd config, flags, file
permissions) against the CIS Kubernetes Benchmark. It must run **on a node with host access**,
so run it in-cluster as a Job/DaemonSet — not from a laptop against a remote API endpoint.

Quick JSON via an in-cluster Job (what `hunt-cluster.sh` does):

```bash
kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: Job
metadata: { name: kube-bench }
spec:
  backoffLimit: 0
  template:
    spec:
      hostPID: true
      restartPolicy: Never
      containers:
        - name: kube-bench
          image: docker.io/aquasec/kube-bench:latest
          command: ["kube-bench","--json"]
          volumeMounts:
            - { name: etc-kubernetes, mountPath: /etc/kubernetes, readOnly: true }
            - { name: var-lib-kubelet, mountPath: /var/lib/kubelet, readOnly: true }
      volumes:
        - { name: etc-kubernetes, hostPath: { path: /etc/kubernetes } }
        - { name: var-lib-kubelet, hostPath: { path: /var/lib/kubelet } }
YAML
kubectl wait --for=condition=complete --timeout=180s job/kube-bench
kubectl logs job/kube-bench > kube-bench.json
```

- Benchmark version is **auto-detected** from the cluster; override with `--benchmark cis-1.9`
  (or `eks-1.2.0`, `gke-1.6.0`, `rke-cis-1.7`, …).
- Target subsets: `--targets master,node,etcd,policies`.
- Managed control planes (EKS/GKE/AKS) hide the master files, so the master checks are limited
  there — focus on the node/policy checks.
- FAIL/WARN counts: `jq '[.Controls[].tests[].results[]|select(.status=="FAIL")]|length'`.

## KubeHound — attack-path graph

KubeHound is the K8s analogue of BloodHound: it collects cluster state (pods, RBAC roles/
bindings, service accounts, endpoints, nodes) and computes **attack paths** (privilege
escalation, lateral movement) into a **JanusGraph** graph DB.

- Needs Docker + Docker Compose (it stands up JanusGraph + MongoDB + a Jupyter UI) and a
  **read-only** kubeconfig (get/list — no cluster-admin required).
- Collection/ingest are scriptable; **analysis is interactive** (Gremlin/DSL queries).

```bash
# install the binary from https://github.com/DataDog/KubeHound/releases/latest
kubehound backend up                 # start JanusGraph + MongoDB + Jupyter
kubehound dump local ./kh-dump       # dump the live cluster (offline collector)
kubehound ingest local ./kh-dump     # load it into the graph
# explore: http://localhost:8888/notebooks/KubeHound.ipynb   (e.g. kh.attacks())
kubehound backend down               # stop the backend when done
```

There is no one-flag JSON export — query the graph (the notebook can serialize query results).
Look for attack paths that reach sensitive workloads, cluster-admin, or node compromise.

## Turning findings into tickets

kube-bench FAIL items map cleanly to CIS control IDs (e.g. `1.2.x`) with a remediation string —
one ticket per FAIL (or per control group). KubeHound findings are attack paths; file a ticket
for each high-value path with the chain of steps and the RBAC/pod change that breaks it.
