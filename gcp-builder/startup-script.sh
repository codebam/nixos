#!/usr/bin/env bash
# GCE startup script for the ephemeral Nix remote builder.
#
# Runs on every boot. Everything here is idempotent: the boot disk survives
# instance stops, so on the second and later boots this is a no-op apart from
# re-installing the systemd units.
set -euxo pipefail

BUILD_USER=builder
CACHE_BUCKET="$(curl -sf -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/nix-cache-bucket || true)"
IDLE_MINUTES="$(curl -sf -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/idle-minutes || echo 10)"
UPSTREAM_CACHES="$(curl -sf -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/upstream-caches ||
  echo 'https://cache.nixos.org https://nyx-cache.chaotic.cx')"
MAX_PATH_BYTES="$(curl -sf -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/max-path-bytes || echo 0)"
UNFREE_NAMES="$(curl -sf -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/attributes/unfree-names || true)"

install_nix() {
  [ -e /nix/var/nix/profiles/default/bin/nix ] && return 0
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y curl xz-utils git ca-certificates
  curl -fsSL -o /tmp/nix-installer \
    https://install.determinate.systems/nix/nix-installer-x86_64-linux
  chmod +x /tmp/nix-installer
  /tmp/nix-installer install linux --no-confirm --init systemd \
    --extra-conf "trusted-users = root ${BUILD_USER}"
}

install_nix

# Nix settings. Written as a separate file so re-runs never duplicate lines and
# the installer's own /etc/nix/nix.conf stays untouched.
mkdir -p /etc/nix
cat >/etc/nix/nix.custom.conf <<EOF
experimental-features = nix-command flakes
trusted-users = root ${BUILD_USER}
max-jobs = auto
cores = 0
# Garbage collect mid-build: once free space drops below min-free, delete until
# max-free is available again. Keeps the boot disk small without a timer race.
min-free = 21474836480
max-free = 107374182400
system-features = nixos-test benchmark big-parallel
substituters = https://cache.nixos.org/ https://nyx-cache.chaotic.cx/
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk=
EOF
grep -q '^!include nix.custom.conf' /etc/nix/nix.conf ||
  printf '\n!include nix.custom.conf\n' >>/etc/nix/nix.conf

id "$BUILD_USER" >/dev/null 2>&1 || useradd -m -s /bin/bash "$BUILD_USER"

# The signing key lets the client trust what this machine built, and lets the
# GCS cache serve paths to the other hosts.
if [ ! -f /etc/nix/cache-priv-key.pem ]; then
  /nix/var/nix/profiles/default/bin/nix-store --generate-binary-cache-key \
    codebam-nix-cache-1 /etc/nix/cache-priv-key.pem /etc/nix/cache-pub-key.pem
  chmod 600 /etc/nix/cache-priv-key.pem
fi

install -m 0755 /dev/stdin /usr/local/bin/nix-cache-push <<'PUSH'
#!/usr/bin/env bash
# Upload every store path that cache.nixos.org does NOT already have.
#
# Deliberately not a plain `nix copy` of the closure: that would re-upload the
# thousands of paths already served by cache.nixos.org, which we pay to store
# and never fetch. --no-recursive uploads exactly the filtered set; the narinfo
# references still point at upstream paths, which clients resolve through
# cache.nixos.org because it stays first in their substituter list.
set -uo pipefail
export PATH=/nix/var/nix/profiles/default/bin:$PATH

BUCKET="${NIX_CACHE_BUCKET:-}"
[ -n "$BUCKET" ] || { echo "no bucket configured"; exit 0; }
UPSTREAM_CACHES="${UPSTREAM_CACHES:-https://cache.nixos.org https://nyx-cache.chaotic.cx}"
# Names the cache must never mirror, from nixpkgs.config.allowUnfreePredicate.
UNFREE_NAMES="${UNFREE_NAMES:-}"
# Paths bigger than this are left to whoever already serves them. Set to 0 to
# disable the cap.
MAX_PATH_BYTES="${MAX_PATH_BYTES:-0}"
# Checked here rather than only in the timer so the pre-shutdown push in
# nix-builder-idle-stop honours the switch too.
[ -e /etc/nix/cache-push-disabled ] && { echo "cache uploads disabled"; exit 0; }

STATE=/var/lib/nix-cache-push
mkdir -p "$STATE"
touch "$STATE/upstream.txt" "$STATE/pushed.txt" "$STATE/skipped.txt"

# Candidates: everything valid locally, minus anything already classified.
nix path-info --all 2>/dev/null | sort -u >"$STATE/all.txt"
sort -u "$STATE/upstream.txt" "$STATE/pushed.txt" "$STATE/skipped.txt" >"$STATE/known.txt"
comm -23 "$STATE/all.txt" "$STATE/known.txt" >"$STATE/candidates.txt"

count=$(wc -l <"$STATE/candidates.txt")
[ "$count" -gt 0 ] || { echo "nothing new to classify"; exit 0; }
echo "classifying $count paths against cache.nixos.org"

# One HEAD per path hash per substituter, 64 at a time. Hits are remembered
# forever, so this only ever runs against genuinely new paths.
#
# Every substituter the clients use has to be checked, not just cache.nixos.org:
# a third of what this machine builds comes from nyx-cache.chaotic.cx, and
# mirroring those would be storage we pay for and never read.
xargs -a "$STATE/candidates.txt" -P 64 -I{} env "SUBS=$UPSTREAM_CACHES" bash -c '
  p="{}"; h="${p#/nix/store/}"; h="${h%%-*}"
  for s in $SUBS; do
    if curl -sf -o /dev/null --max-time 20 "${s%/}/${h}.narinfo"; then
      echo "UP $p"; exit 0
    fi
  done
  echo "MISS $p"' >"$STATE/classified.txt"

grep '^UP ' "$STATE/classified.txt" | cut -d' ' -f2- >>"$STATE/upstream.txt"
grep '^MISS ' "$STATE/classified.txt" | cut -d' ' -f2- | sort -u >"$STATE/missing.txt"
sort -u -o "$STATE/upstream.txt" "$STATE/upstream.txt"

# Absent from every upstream cache is not the same as worth storing. Drop:
#
#   - unfree packages. Upstream cannot cache these because their licences
#     forbid redistribution, which is exactly why they show up here. The list
#     comes from the same allowUnfreePredicate the config uses, passed in as
#     instance metadata, so it cannot drift from what nixpkgs considers unfree.
#   - -debug outputs, which are gigabytes of symbols nothing substitutes.
grep -v -- '-debug$' "$STATE/missing.txt" >"$STATE/missing-keep.txt" || true

# Prefix match on the name, not the full store path: the unfree list holds
# nixpkgs names ("android-studio") while the store holds name-version, and
# sometimes a variant ("android-studio-unwrapped-2026.1.2.11").
awk -v names="$UNFREE_NAMES" '
  BEGIN { n = split(names, a, /[ \t\n]+/) }
  {
    base = $0
    sub(/^\/nix\/store\/[a-z0-9]+-/, "", base)
    for (i = 1; i <= n; i++) {
      if (a[i] == "") continue
      if (base == a[i] || index(base, a[i] "-") == 1) next
    }
    print
  }' "$STATE/missing-keep.txt" | sort -u >"$STATE/missing-filtered.txt"

# Optional size cap. The paths this catches are vendor blobs -- android-studio,
# chrome, discord -- which are a fast download from the vendor and by far the
# largest thing we would be paying to store.
if [ "$MAX_PATH_BYTES" -gt 0 ] && [ -s "$STATE/missing-filtered.txt" ]; then
  xargs -a "$STATE/missing-filtered.txt" -n 256 -r nix-store --query --size >"$STATE/f-sizes.txt"
  paste -d' ' "$STATE/f-sizes.txt" "$STATE/missing-filtered.txt" |
    awk -v cap="$MAX_PATH_BYTES" '$1 <= cap {print $2}' >"$STATE/under-cap.txt"
  mv "$STATE/under-cap.txt" "$STATE/missing-filtered.txt"
fi

# Everything filtered out is still recorded, so it is not reclassified forever.
comm -23 "$STATE/missing.txt" "$STATE/missing-filtered.txt" >>"$STATE/skipped.txt"
sort -u -o "$STATE/skipped.txt" "$STATE/skipped.txt"
mv "$STATE/missing-filtered.txt" "$STATE/missing.txt"

missing=$(wc -l <"$STATE/missing.txt")
echo "$missing paths worth uploading (of $(wc -l <"$STATE/candidates.txt") classified)"
[ "$missing" -gt 0 ] || exit 0

# Sign first: --no-recursive skips nix's own closure signing pass.
xargs -a "$STATE/missing.txt" -r nix store sign --key-file /etc/nix/cache-priv-key.pem

# Staged through a local binary cache, then uploaded with gcloud. Writing
# straight to s3:// would mean putting GCS HMAC keys on this disk; gcloud
# authenticates as the instance's own service account instead.
STAGE="$(mktemp -d /var/tmp/nix-push.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT

# A binary cache refuses a path whose references it does not already hold, and
# ours deliberately reference paths served by cache.nixos.org. So stub every
# path we are not pushing. The stubs have to parse as real narinfo -- nix reads
# them, it does not just stat them -- but only StorePath/NarHash/NarSize are
# load-bearing, and every stub is removed again before anything is uploaded.
comm -23 "$STATE/all.txt" "$STATE/missing.txt" >"$STATE/stubs.txt"
xargs -a "$STATE/stubs.txt" -n 256 -r nix-store --query --hash >"$STATE/stub-hashes.txt"
xargs -a "$STATE/stubs.txt" -n 256 -r nix-store --query --size >"$STATE/stub-sizes.txt"
paste -d' ' "$STATE/stubs.txt" "$STATE/stub-hashes.txt" "$STATE/stub-sizes.txt" |
  awk -v stage="$STAGE" '
    NF == 3 {
      hash = $1; sub(/^\/nix\/store\//, "", hash); sub(/-.*$/, "", hash)
      f = stage "/" hash ".narinfo"
      printf "StorePath: %s\nURL: nar/stub\nCompression: none\nNarHash: %s\nNarSize: %s\n", $1, $2, $3 >f
      close(f)
      print hash ".narinfo"
    }' >"$STAGE/.stub-list"

# Dependencies first, so a missing path that references another missing path
# still finds it staged. nix-store -qR emits requisites in topological order.
xargs -a "$STATE/missing.txt" -r nix-store --query --requisites 2>/dev/null |
  awk '!seen[$0]++' >"$STATE/order.txt"
grep -Fxf "$STATE/missing.txt" "$STATE/order.txt" >"$STATE/missing-ordered.txt" ||
  cp "$STATE/missing.txt" "$STATE/missing-ordered.txt"

# zstd, not the xz default: xz spends minutes single-threaded on a multi-GB
# path for a few percent of size we would only pay egress on once.
if ! xargs -a "$STATE/missing-ordered.txt" -r nix copy --no-recursive \
  --to "file://$STAGE?compression=zstd&secret-key=/etc/nix/cache-priv-key.pem"; then
  echo "staging failed; will retry next run" >&2
  exit 1
fi

# Drop the stubs before upload -- they describe paths we are not serving, and a
# client that fetched one would get a narinfo pointing at a nar that isn't there.
while read -r f; do rm -f "$STAGE/$f"; done <"$STAGE/.stub-list"
rm -f "$STAGE/.stub-list"

# nix creates empty log/ and realisations/ directories; gcloud treats a path
# that matches nothing as an error and fails the whole copy.
find "$STAGE" -type d -empty -delete

if gcloud storage cp -r "$STAGE"/* "gs://$BUCKET/" >/dev/null; then
  cat "$STATE/missing.txt" >>"$STATE/pushed.txt"
  sort -u -o "$STATE/pushed.txt" "$STATE/pushed.txt"
  echo "uploaded $missing paths"
else
  echo "upload failed; will retry next run" >&2
  exit 1
fi
PUSH

install -m 0755 /dev/stdin /usr/local/bin/nix-builder-idle-stop <<'IDLE'
#!/usr/bin/env bash
# Stop the instance once nothing has used it for IDLE_MINUTES consecutive
# checks. Stopping (rather than deleting) keeps the warm /nix/store on the boot
# disk; a stopped instance bills for disk only.
set -uo pipefail
IDLE_MINUTES="${IDLE_MINUTES:-10}"
COUNTER=/run/nix-builder-idle

busy() {
  # Someone connected over SSH...
  [ "$(ss -H -t state established '( sport = :22 )' 2>/dev/null | wc -l)" -gt 0 ] && return 0
  # ...or a build is still running without a live connection.
  pgrep -x nix-build >/dev/null && return 0
  pgrep -f 'nix-daemon --daemon' >/dev/null && {
    # nix-daemon always runs; count only its forked worker children.
    [ "$(pgrep -P "$(pgrep -f 'nix-daemon --daemon' | head -1)" | wc -l)" -gt 0 ] && return 0
  }
  return 1
}

if busy; then
  echo 0 >"$COUNTER"
  exit 0
fi

n=$(( $(cat "$COUNTER" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$COUNTER"
[ "$n" -ge "$IDLE_MINUTES" ] || exit 0

echo "idle for ${n}m; pushing cache then powering off"
systemctl start --wait nix-cache-push.service || true
exec shutdown -h now
IDLE

mkdir -p /etc/systemd/system

cat >/etc/systemd/system/nix-cache-push.service <<EOF
[Unit]
Description=Push locally-built store paths to the GCS binary cache
After=network-online.target nix-daemon.service

[Service]
Type=oneshot
Environment=NIX_CACHE_BUCKET=${CACHE_BUCKET}
Environment=MAX_PATH_BYTES=${MAX_PATH_BYTES}
# Quoted: these are space-separated lists, and systemd splits an unquoted
# Environment= value on whitespace into separate assignments.
Environment="UPSTREAM_CACHES=${UPSTREAM_CACHES}"
Environment="UNFREE_NAMES=${UNFREE_NAMES}"
ExecStart=/usr/local/bin/nix-cache-push
TimeoutStartSec=3600
EOF

cat >/etc/systemd/system/nix-cache-push.timer <<'EOF'
[Unit]
Description=Periodic binary cache push

[Timer]
OnBootSec=15min
OnUnitActiveSec=15min

[Install]
WantedBy=timers.target
EOF

cat >/etc/systemd/system/nix-builder-idle-stop.service <<EOF
[Unit]
Description=Stop this instance when idle

[Service]
Type=oneshot
Environment=IDLE_MINUTES=${IDLE_MINUTES}
ExecStart=/usr/local/bin/nix-builder-idle-stop
EOF

cat >/etc/systemd/system/nix-builder-idle-stop.timer <<'EOF'
[Unit]
Description=Idle check every minute

[Timer]
OnBootSec=5min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

cat >/etc/systemd/system/nix-gc.service <<'EOF'
[Unit]
Description=Aggressive nix garbage collection

[Service]
Type=oneshot
ExecStart=/nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 2d
EOF

cat >/etc/systemd/system/nix-gc.timer <<'EOF'
[Unit]
Description=Garbage collect the builder store

[Timer]
OnBootSec=30min
OnUnitActiveSec=6h

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now nix-cache-push.timer nix-builder-idle-stop.timer nix-gc.timer
systemctl restart nix-daemon.service || true

echo "builder ready" >/var/run/nix-builder-ready
