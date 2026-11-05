#!/bin/bash
# ============================================================
#  GSP766 - Managing a GKE Multi-tenant Cluster with Namespaces
#  Auto-runner untuk Google Cloud Skills Boost / Qwiklabs
#  Credit: Jutapen
# ============================================================
set -e

pause() { echo; read -r -p ">>> Klik 'Check my progress' ($1), setelah itu tekan ENTER untuk lanjut... " _ </dev/tty; echo; }

export ZONE=us-east1-c
export PROJECT="${GOOGLE_CLOUD_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
[ -n "$PROJECT" ] || { echo "Project ID tidak ditemukan. Jalankan di Cloud Shell lab."; exit 1; }
SA="team-a-dev@${PROJECT}.iam.gserviceaccount.com"

echo "=== Task 1: Download required files ==="
[ -d ~/gke-qwiklab ] || gcloud storage cp -r gs://spls/gsp766/gke-qwiklab ~
cd ~/gke-qwiklab

echo "=== Task 2: View and create namespaces ==="
gcloud config set compute/zone ${ZONE}
gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE}
kubectl get namespace
kubectl get ns team-a >/dev/null 2>&1 || kubectl create namespace team-a
kubectl get ns team-b >/dev/null 2>&1 || kubectl create namespace team-b
kubectl get pod app-server -n team-a >/dev/null 2>&1 || \
  kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity
kubectl get pod app-server -n team-b >/dev/null 2>&1 || \
  kubectl run app-server --image=quay.io/centos/centos:9 --namespace=team-b -- sleep infinity
kubectl get pods -A
kubectl describe pod app-server --namespace=team-a | head -20
kubectl config set-context --current --namespace=team-a
pause "Task 2 - Create namespaces"

echo "=== Task 3: Access control in namespaces ==="
gcloud projects add-iam-policy-binding ${PROJECT} \
  --member=serviceAccount:${SA} \
  --role=roles/container.clusterViewer \
  --condition=None >/dev/null
echo "IAM binding OK"

kubectl get role pod-reader -n team-a >/dev/null 2>&1 || \
  kubectl create role pod-reader --resource=pods --verb=watch --verb=get --verb=list -n team-a
cat developer-role.yaml
kubectl get role developer -n team-a >/dev/null 2>&1 || kubectl create -f developer-role.yaml
kubectl get rolebinding team-a-developers -n team-a >/dev/null 2>&1 || \
  kubectl create rolebinding team-a-developers --role=developer --user=${SA} -n team-a

make_key() {
  rm -f /tmp/key.json
  gcloud iam service-accounts keys create /tmp/key.json --iam-account ${SA}
}
[ -s /tmp/key.json ] || make_key
pause "Task 3 - Access Control in namespaces"

echo "--- Tes login sebagai team-a-dev (config terpisah, akun utama tidak berubah) ---"
mkdir -p /tmp/sa-gcloud
activate_ok=0
for round in 1 2; do
  for i in 1 2 3 4 5 6 7 8; do
    if CLOUDSDK_CONFIG=/tmp/sa-gcloud gcloud auth activate-service-account --key-file=/tmp/key.json 2>/dev/null; then
      activate_ok=1; break
    fi
    echo "Key belum aktif (propagasi), coba lagi dalam 15 detik... ($i/8)"
    sleep 15
  done
  [ "$activate_ok" = 1 ] && break
  echo "Membuat key baru lalu mencoba lagi..."
  make_key
done
[ "$activate_ok" = 1 ] || { echo "Gagal activate service account"; exit 1; }

(
  export CLOUDSDK_CONFIG=/tmp/sa-gcloud
  export KUBECONFIG=/tmp/sa-kube
  gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${PROJECT}
  ok=0
  for i in 1 2 3 4 5 6; do
    if kubectl get pods --namespace=team-a; then ok=1; break; fi
    echo "Izin belum menyebar, coba lagi 15 detik..."; sleep 15
  done
  [ "$ok" = 1 ] || echo "PERINGATAN: team-a gagal diakses"
  echo "--- team-b (HARUS Forbidden) ---"
  if kubectl get pods --namespace=team-b; then
    echo "PERINGATAN: seharusnya ditolak"
  else
    echo "OK: akses team-b ditolak seperti yang diharapkan"
  fi
)

gcloud container clusters get-credentials multi-tenant-cluster --zone ${ZONE} --project ${PROJECT}
kubectl config set-context --current --namespace=team-a

echo "=== Task 4: Resource quotas ==="
if ! kubectl get quota test-quota -n team-a >/dev/null 2>&1; then
  kubectl create quota test-quota --hard=count/pods=2,count/services.loadbalancers=1 --namespace=team-a
  kubectl get pod app-server-2 -n team-a >/dev/null 2>&1 || \
    kubectl run app-server-2 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity
  echo "--- pod ke-3 (HARUS error exceeded quota) ---"
  kubectl run app-server-3 --image=quay.io/centos/centos:9 --namespace=team-a -- sleep infinity || \
    echo "OK: error quota seperti yang diharapkan"
fi
kubectl describe quota test-quota --namespace=team-a
kubectl patch quota test-quota -n team-a --type merge -p '{"spec":{"hard":{"count/pods":"6"}}}'
kubectl describe quota test-quota --namespace=team-a

kubectl get quota cpu-mem-quota -n team-a >/dev/null 2>&1 || kubectl create -f cpu-mem-quota.yaml
kubectl get pod cpu-mem-demo -n team-a >/dev/null 2>&1 || \
  kubectl create -f cpu-mem-demo-pod.yaml --namespace=team-a
kubectl describe quota cpu-mem-quota --namespace=team-a
pause "Task 4 - Resource quotas"

echo "=== Task 5: GKE usage metering ==="
gcloud container clusters update multi-tenant-cluster --zone ${ZONE} \
  --resource-usage-bigquery-dataset cluster_dataset

export GCP_BILLING_EXPORT_TABLE_FULL_PATH=${PROJECT}.billing_dataset.gcp_billing_export_v1_xxxx
export USAGE_METERING_DATASET_ID=cluster_dataset
export COST_BREAKDOWN_TABLE_ID=usage_metering_cost_breakdown
export USAGE_METERING_QUERY_TEMPLATE=~/gke-qwiklab/usage_metering_query_template.sql
export USAGE_METERING_QUERY=cost_breakdown_query.sql
export USAGE_METERING_START_DATE=2020-10-26

sed \
  -e "s/\${fullGCPBillingExportTableID}/$GCP_BILLING_EXPORT_TABLE_FULL_PATH/" \
  -e "s/\${projectID}/$PROJECT/" \
  -e "s/\${datasetID}/$USAGE_METERING_DATASET_ID/" \
  -e "s/\${startDate}/$USAGE_METERING_START_DATE/" \
  "$USAGE_METERING_QUERY_TEMPLATE" > "$USAGE_METERING_QUERY"

LOC=$(bq show --format=json ${PROJECT}:${USAGE_METERING_DATASET_ID} | jq -r .location | tr 'A-Z' 'a-z')
EXISTS=$(bq ls --transfer_config --transfer_location=${LOC} --project_id=${PROJECT} --format=json 2>/dev/null \
  | jq -r '.[]? | select(.displayName=="GKE Usage Metering Cost Breakdown Scheduled Query") | .name' || true)

if [ -z "$EXISTS" ]; then
  echo ">>> Jika muncul link otorisasi: klik, login pakai akun student, lalu paste version_info ke sini."
  bq query \
    --project_id=$PROJECT \
    --use_legacy_sql=false \
    --destination_table=$USAGE_METERING_DATASET_ID.$COST_BREAKDOWN_TABLE_ID \
    --schedule='every 24 hours' \
    --display_name="GKE Usage Metering Cost Breakdown Scheduled Query" \
    --replace=true \
    "$(cat $USAGE_METERING_QUERY)"
else
  echo "Scheduled query sudah ada, dilewati: $EXISTS"
fi

cat <<EOF

=== SELESAI bagian CLI ===
Langkah manual (GUI) sebelum cek progres Task 5:
1. Looker Studio > Create > Data Source > BigQuery > CUSTOM QUERY
   Nama data source: GKE Usage
   Query:
   SELECT * FROM \`${PROJECT}.cluster_dataset.usage_metering_cost_breakdown\`
   lalu klik CONNECT.
2. (Opsional) Monitoring > Dashboards > GKE untuk melihat penggunaan per namespace.

Credit: Jutapen
EOF
pause "Task 5 - Monitoring GKE and GKE usage metering"
echo "Semua selesai. Credit: Jutapen"
