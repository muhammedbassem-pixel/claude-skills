#!/usr/bin/env bash
# Hunt security issues on a LIVE Kubernetes cluster:
#   - kube-bench : CIS Kubernetes Benchmark (runs as an in-cluster Job with host access)
#   - KubeHound  : attack-path graph (stands up a JanusGraph/Mongo/Jupyter backend; interactive)
# Requires a working kubeconfig/context pointing at the target cluster.
# Usage: hunt-cluster.sh [-H] [-o output-dir]
#   (default) run kube-bench and collect its JSON
#   -H        also set up KubeHound (backend up + dump + ingest) for attack-path analysis
set -euo pipefail

RUN_KUBEHOUND=0
OUTDIR=""
while getopts "Ho:" opt; do
  case $opt in
    H) RUN_KUBEHOUND=1 ;;
    o) OUTDIR="$OPTARG" ;;
    *) echo "usage: hunt-cluster.sh [-H] [-o output-dir]" >&2; exit 1 ;;
  esac
done

command -v kubectl >/dev/null || { echo "kubectl not installed" >&2; exit 1; }
kubectl cluster-info >/dev/null 2>&1 || { echo "No reachable cluster (check your kubeconfig/context)" >&2; exit 1; }
CTX="$(kubectl config current-context 2>/dev/null || echo unknown)"

TS=$(date +%Y%m%d_%H%M%S)
OUT="${OUTDIR:-$HOME/k8s-scan/cluster_${TS}}"
mkdir -p "$OUT"
echo ">> Target context: $CTX"
echo ">> WARNING: this runs against a LIVE cluster. Only proceed if authorized."

# ---- kube-bench: CIS benchmark as an in-cluster Job (needs node host access) ----
KB_IMAGE="${KUBE_BENCH_IMAGE:-docker.io/aquasec/kube-bench:latest}"
JOB="kube-bench-${TS}"
echo ">> Running kube-bench ($KB_IMAGE) as Job/$JOB ..."
cat <<YAML | kubectl apply -f - >/dev/null
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
spec:
  backoffLimit: 0
  template:
    spec:
      hostPID: true
      restartPolicy: Never
      containers:
        - name: kube-bench
          image: ${KB_IMAGE}
          command: ["kube-bench","--json"]
          volumeMounts:
            - { name: var-lib-etcd,     mountPath: /var/lib/etcd,     readOnly: true }
            - { name: var-lib-kubelet,  mountPath: /var/lib/kubelet,  readOnly: true }
            - { name: etc-kubernetes,   mountPath: /etc/kubernetes,   readOnly: true }
            - { name: etc-systemd,      mountPath: /etc/systemd,      readOnly: true }
      volumes:
        - { name: var-lib-etcd,    hostPath: { path: /var/lib/etcd } }
        - { name: var-lib-kubelet, hostPath: { path: /var/lib/kubelet } }
        - { name: etc-kubernetes,  hostPath: { path: /etc/kubernetes } }
        - { name: etc-systemd,     hostPath: { path: /etc/systemd } }
YAML

echo ">> Waiting for kube-bench to finish (up to 180s)..."
kubectl wait --for=condition=complete --timeout=180s "job/${JOB}" 2>/dev/null || \
  echo "   (job did not report complete in time — collecting whatever logs exist)"
kubectl logs "job/${JOB}" > "$OUT/kube-bench.json" 2>/dev/null || true
kubectl delete "job/${JOB}" --wait=false >/dev/null 2>&1 || true

if [ -s "$OUT/kube-bench.json" ] && jq -e . "$OUT/kube-bench.json" >/dev/null 2>&1; then
  FAIL=$(jq '[.Controls[]?.tests[]?.results[]?|select(.status=="FAIL")]|length' "$OUT/kube-bench.json" 2>/dev/null || echo '?')
  WARN=$(jq '[.Controls[]?.tests[]?.results[]?|select(.status=="WARN")]|length' "$OUT/kube-bench.json" 2>/dev/null || echo '?')
  echo ">> kube-bench: $FAIL FAIL, $WARN WARN (see kube-bench.json)"
else
  echo ">> kube-bench produced no parseable JSON — the Job may need a node with host access"
  echo "   (managed control planes like EKS/GKE restrict the master checks)."
fi

# ---- KubeHound: attack-path graph (heavy, interactive) ----
if [ "$RUN_KUBEHOUND" = 1 ]; then
  echo
  echo ">> KubeHound setup (attack-path graph)."
  docker info >/dev/null 2>&1 || { echo "   Docker not running — required for the KubeHound backend." >&2; exit 1; }
  if ! command -v kubehound >/dev/null; then
    echo "   The 'kubehound' binary is not installed. Install it from:"
    echo "     https://github.com/DataDog/KubeHound/releases/latest"
    echo "   then re-run with -H. Skipping KubeHound."
  else
    echo ">> Bringing up the KubeHound backend (JanusGraph + MongoDB + Jupyter)..."
    kubehound backend up
    echo ">> Dumping live cluster + ingesting into the graph..."
    kubehound dump local "$OUT/kubehound-dump" || true
    kubehound ingest local "$OUT/kubehound-dump" || true
    echo ">> KubeHound ready. Explore attack paths at http://localhost:8888/notebooks/KubeHound.ipynb"
    echo "   (Gremlin/DSL, e.g. kh.attacks() ). Backend stays up until: kubehound backend down"
  fi
fi

echo
echo ">> Cluster-hunt output in $OUT:"
for f in "$OUT"/*; do [ -e "$f" ] && echo "   ${f##*/}"; done
