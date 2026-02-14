# MAS Dockerfile patch

This directory contains patches we apply on top of the upstream **Matrix Authentication Service** submodule (`docker/chat/mas/repo`) to make local/dev builds **much less RAM-hungry** and configurable.

## What the patch does

`patch-dockerfile.patch` modifies the upstream `docker/chat/mas/repo/Dockerfile` to:

- **Expose Rust build knobs as Docker build args/env**:
  - `CARGO_BUILD_JOBS` (limits parallel rustc)
  - `CARGO_PROFILE_RELEASE_LTO` (disable/enable LTO)
  - `CARGO_PROFILE_RELEASE_CODEGEN_UNITS` (raise for lower peak RAM)
  - `MAS_BUILD_TARGETS` (build one arch instead of both)
- **Build only the requested targets** and move only those binaries.

Why it matters: upstream MAS enables **fat LTO + codegen-units=1** in release and the Dockerfile builds **amd64 + arm64** in one step. That combination can spawn many `rustc` processes and spike RAM hard.

## Applying the patch (idempotent)

Run from the repo root:

```bash
MAS_REPO="docker/chat/mas/repo"
MAS_PATCH="$(realpath docker/chat/mas/patches/patch-dockerfile.patch)"

# If reverse-check succeeds, patch is already applied.
if git -C "$MAS_REPO" apply --reverse --check "$MAS_PATCH" >/dev/null 2>&1; then
  echo "MAS Dockerfile patch already applied"
else
  git -C "$MAS_REPO" apply "$MAS_PATCH"
fi
```

## Buildx vs “classic” docker build

- Most modern Docker setups route `docker build` through **BuildKit/buildx**.
  - In that mode you generally **can’t** rely on `docker build --cpus/--memory` flags to protect your host.
- If you truly use a legacy builder that supports those flags, you _might_ get away without this patch by hard-capping Docker’s resources.

Even without buildx, the patch is still useful because it changes the **Rust build itself** (targets, jobs, LTO), which is what actually drives `rustc` RAM usage.

## Tuning (use more RAM next time)

If you want the next build to use more of your 16GB and finish faster, increase parallelism:

- **Faster / more RAM**:
  - `CARGO_BUILD_JOBS=4` (or `8`, depending on cores/RAM)
  - Optionally build both targets: `MAS_BUILD_TARGETS="x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu"`
- **Fastest but can spike RAM a lot** (closer to upstream):
  - `CARGO_PROFILE_RELEASE_LTO=true`
  - `CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1`

These are wired through `docker/chat/mas/build.sh` via `--build-arg ...`.
