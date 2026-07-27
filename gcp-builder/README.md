# GCP remote build server

An on-demand GCE spot instance that builds this flake, plus a GCS binary cache
holding only the paths `cache.nixos.org` does not already serve.

## What runs where

| Piece | Where |
| --- | --- |
| `services.gcpNixBuilder` module | `modules/system/gcp-nix-builder.nix` |
| Enabled for desktop + laptop | `desktop-laptop/configuration/gcp-nix-builder.nix` |
| Resource creation / repair | `gcp-builder/bootstrap.sh` |
| Instance provisioning | `gcp-builder/startup-script.sh` (GCE metadata) |

Project `codebam-nixbuild`, instance `nix-builder` in `us-east1-b`,
bucket `gs://codebam-nix-cache`.

## Using it

`nixos-rebuild switch` already offloads: the module registers the builder in
`nix.buildMachines`, and the `ProxyCommand` starts the instance on the first
connection. Nothing else to type.

To force the *entire* closure remote rather than letting nix schedule by
`speedFactor`:

```
gcp-nix-builder rebuild switch
```

Other subcommands:

```
gcp-nix-builder status     # instance state, address, cost guard
gcp-nix-builder up|down    # start / (push cache, then) stop
gcp-nix-builder off|on     # cost guard: off makes builds stay local
gcp-nix-builder ssh|log    # shell in, or read the startup-script journal
gcp-nix-builder push|gc    # run the cache push / garbage collection now
gcp-nix-builder cache ...  # on | off | status | size | purge
```

### Turning the cache off

```
gcp-nix-builder cache off     # stop uploading; existing objects stay
gcp-nix-builder cache size    # what the bucket is costing you
gcp-nix-builder cache purge   # delete everything in it (prompts)
```

Storage and class-A operations are what the bucket bills for, so stopping
uploads is the switch that matters, and it takes effect immediately without a
rebuild. Reads keep working against whatever is already there. To also drop the
bucket from this machine's substituter list, set
`services.gcpNixBuilder.cache.useAsSubstituter = false` and rebuild — that one
is build-time because it lands in `/etc/nix/nix.conf`.

## Cost shape

The instance is Spot (`--provisioning-model=SPOT`) and stops itself after 10
idle minutes, so it bills roughly per build:

- `c2d-standard-32` spot: **~$0.35/hr** while building (~$1.40/hr on demand).
- 100 GB pd-balanced boot disk: **~$10/month**, the only cost while stopped.
- Egress: the largest variable. `builders-use-substitutes` is already on in
  `modules/system/nix.nix`, so the builder pulls dependencies straight from
  `cache.nixos.org` instead of routing them through your uplink; only paths it
  actually built come back to you.

Stopping rather than deleting keeps `/nix/store` warm on the boot disk, which
is what makes the second build of the day fast. Preemption uses
`--instance-termination-action=STOP` for the same reason, and
`--max-run-duration=6h` is the backstop against a build that never finishes.

`c2d` rather than `n2d`: a fresh project is capped at 16 N2D vCPUs in
`us-east1` but 100 C2D vCPUs, and c2d's higher clock suits compiles that don't
parallelise.

## Cache contents

`nix-cache-push` on the instance uploads a path only if
`https://cache.nixos.org/<hash>.narinfo` 404s, so the bucket holds just the
things upstream cannot give you — your own packages, overlays, and anything
from an input that isn't cached. It uses `nix copy --no-recursive`, because a
plain closure copy would drag in the thousands of upstream paths we would then
pay to store and never fetch. The narinfos still reference those upstream
paths; clients resolve them through `cache.nixos.org`, which stays first in the
substituter list.

Classification results are memoised in `/var/lib/nix-cache-push`, so repeat
runs only probe genuinely new paths. It runs every 15 minutes, and once more
immediately before the idle shutdown.

Two details worth knowing before editing it. A binary cache refuses any path
whose references it does not already hold, so the script first writes stub
narinfos for every path it is *not* pushing — nix parses those, it does not
merely stat them — and deletes the stubs again before upload. And the upload
stages into a local `file://` cache which `gcloud storage` then copies, rather
than writing to `s3://` directly: that way the instance authenticates as its
own service account and no GCS HMAC key has to live on its disk.

## Garbage collection

- On the instance: `min-free`/`max-free` (20 GB / 100 GB) makes nix collect
  mid-build when the disk tightens, plus a `nix-gc.timer` running
  `nix-collect-garbage --delete-older-than 2d` every 6 hours.
- In the bucket: a 30-day object lifecycle rule. An expired path is simply
  rebuilt and re-pushed the next time something needs it.

## Credentials

`/var/lib/gcp-nix-builder` (preserved to `/persistent`, `0750 root:wheel`):

| File | Purpose |
| --- | --- |
| `sa.json` | control service account; the `ProxyCommand` uses it to start the instance |
| `id_ed25519` | build user's SSH key — `0600 root:root`, ssh rejects anything looser |
| `aws-credentials` | GCS HMAC pair for the `s3://` substituter, read by nix-daemon |
| `known_hosts` | pinned host key |

Re-run `gcp-builder/bootstrap.sh` to recreate all of it; it is idempotent.

## Rebuilding the instance from scratch

```
gcloud compute instances delete nix-builder --zone us-east1-b --project codebam-nixbuild
./gcp-builder/bootstrap.sh
```

The startup script is idempotent and re-runs on every boot, so editing it and
running `bootstrap.sh` is enough to push changes to an existing instance.
