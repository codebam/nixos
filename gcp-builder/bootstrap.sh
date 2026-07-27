#!/usr/bin/env bash
# Create (or repair) every GCP resource the remote builder needs.
#
# Idempotent: safe to re-run. Prints the two values that have to be copied into
# modules/system/gcp-nix-builder.nix if they ever change (cache signing key) or
# into /var/lib/gcp-nix-builder (credentials).
set -euo pipefail

PROJECT="${PROJECT:-codebam-nixbuild}"
BILLING_ACCOUNT="${BILLING_ACCOUNT:-016D37-AC19E8-F3E311}"
ZONE="${ZONE:-us-east1-b}"
REGION="${REGION:-${ZONE%-*}}"
INSTANCE="${INSTANCE:-nix-builder}"
BUCKET="${BUCKET:-codebam-nix-cache}"
# c2d, not n2d: a fresh project gets 16 N2D vCPUs but 100 C2D vCPUs in
# us-east1, and c2d's higher clock suits mostly-serial compiles.
MACHINE_TYPE="${MACHINE_TYPE:-c2d-standard-32}"
DISK_SIZE="${DISK_SIZE:-100GB}"
IDLE_MINUTES="${IDLE_MINUTES:-10}"
STATE_DIR="${STATE_DIR:-/var/lib/gcp-nix-builder}"
SA="nix-builder-ctl@${PROJECT}.iam.gserviceaccount.com"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# This host has no sudo; polkit's run0 is the escalation path.
as_root() { run0 --no-ask-password "$@"; }
g() { gcloud --project="$PROJECT" --quiet "$@"; }

echo "==> project"
gcloud projects describe "$PROJECT" >/dev/null 2>&1 ||
  gcloud projects create "$PROJECT" --name="NixOS Build Server"
gcloud billing projects link "$PROJECT" --billing-account="$BILLING_ACCOUNT" >/dev/null
g services enable compute.googleapis.com storage.googleapis.com iam.googleapis.com

echo "==> service account"
g iam service-accounts describe "$SA" >/dev/null 2>&1 ||
  g iam service-accounts create nix-builder-ctl --display-name="Nix builder control"
for role in roles/compute.instanceAdmin.v1 roles/iam.serviceAccountUser roles/storage.admin; do
  g projects add-iam-policy-binding "$PROJECT" \
    --member="serviceAccount:$SA" --role="$role" --condition=None >/dev/null
done

echo "==> cache bucket"
g storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 ||
  g storage buckets create "gs://$BUCKET" --location="$REGION" \
    --default-storage-class=STANDARD --uniform-bucket-level-access
# Objects age out rather than accumulating forever. A path deleted here is
# simply rebuilt and re-pushed the next time something needs it.
g storage buckets update "gs://$BUCKET" --lifecycle-file=/dev/stdin <<'EOF'
{"lifecycle":{"rule":[{"action":{"type":"Delete"},"condition":{"age":30}}]}}
EOF
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')"
g storage buckets add-iam-policy-binding "gs://$BUCKET" \
  --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" \
  --role=roles/storage.objectAdmin >/dev/null

echo "==> ssh key"
[ -f ~/.ssh/id_gcp_nix_builder ] ||
  ssh-keygen -t ed25519 -N "" -C nix-remote-builder -f ~/.ssh/id_gcp_nix_builder

echo "==> instance"
if ! g compute instances describe "$INSTANCE" --zone="$ZONE" >/dev/null 2>&1; then
  keyfile="$(mktemp)"
  printf 'builder:%s\n' "$(cat ~/.ssh/id_gcp_nix_builder.pub)" >"$keyfile"
  # SPOT + STOP: preemption parks the instance instead of destroying the warm
  # /nix/store. max-run-duration is the backstop against a runaway build.
  g compute instances create "$INSTANCE" --zone="$ZONE" \
    --machine-type="$MACHINE_TYPE" \
    --provisioning-model=SPOT --instance-termination-action=STOP \
    --max-run-duration=6h \
    --image-family=debian-12 --image-project=debian-cloud \
    --boot-disk-size="$DISK_SIZE" --boot-disk-type=pd-balanced \
    --scopes=https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/logging.write \
    --metadata="enable-oslogin=FALSE,nix-cache-bucket=$BUCKET,idle-minutes=$IDLE_MINUTES" \
    --metadata-from-file="ssh-keys=$keyfile,startup-script=$HERE/startup-script.sh"
  rm -f "$keyfile"
else
  # Keep an existing instance's startup script in sync with this repo.
  g compute instances add-metadata "$INSTANCE" --zone="$ZONE" \
    --metadata-from-file="startup-script=$HERE/startup-script.sh"
fi

IP="$(g compute instances describe "$INSTANCE" --zone="$ZONE" \
  --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
echo "    instance at $IP"

echo "==> waiting for the builder to finish provisioning"
for _ in $(seq 1 60); do
  ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
    -i ~/.ssh/id_gcp_nix_builder "builder@$IP" 'test -e /var/run/nix-builder-ready' 2>/dev/null && break
  sleep 10
done

echo "==> credentials into $STATE_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gcloud iam service-accounts keys create "$tmp/sa.json" --iam-account="$SA" --project="$PROJECT"
# GCS's S3 interop endpoint is how nix talks to the bucket; that needs HMAC
# credentials rather than the JSON key.
hmac="$(g storage hmac create "$SA" --format=json)"
cat >"$tmp/aws-credentials" <<EOF
[default]
aws_access_key_id = $(echo "$hmac" | jq -r .metadata.accessId)
aws_secret_access_key = $(echo "$hmac" | jq -r .secret)
EOF
ssh-keyscan -H "$IP" >"$tmp/known_hosts" 2>/dev/null

for d in "$STATE_DIR" "/persistent$STATE_DIR"; do
  as_root mkdir -p "$d"
  as_root install -m 0640 -o root -g wheel "$tmp/sa.json" "$d/sa.json"
  as_root install -m 0640 -o root -g wheel "$tmp/aws-credentials" "$d/aws-credentials"
  as_root install -m 0640 -o root -g wheel "$tmp/known_hosts" "$d/known_hosts"
  # ssh refuses a private key that any other user can read.
  as_root install -m 0600 -o root -g root ~/.ssh/id_gcp_nix_builder "$d/id_ed25519"
  as_root chgrp wheel "$d"
  as_root chmod 0750 "$d"
done
# nix-daemon builds as root, so root is the one that verifies the host key.
as_root sh -c "mkdir -p /root/.ssh && chmod 700 /root/.ssh &&
  cat '$STATE_DIR/known_hosts' >> /root/.ssh/known_hosts &&
  sort -u -o /root/.ssh/known_hosts /root/.ssh/known_hosts"

echo
echo "cache public key (set services.gcpNixBuilder.cache.publicKey to this):"
ssh -o StrictHostKeyChecking=no -i ~/.ssh/id_gcp_nix_builder "builder@$IP" \
  'cat /etc/nix/cache-pub-key.pem'
