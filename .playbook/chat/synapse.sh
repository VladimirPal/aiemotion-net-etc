#@ssh host=root.aiemotion.net

#@group "Synapse static secret files"

#@step "Generate registration shared secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_REGISTRATION_SECRET_FILENAME=synapse-registration-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_REGISTRATION_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate macaroon secret key"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_MACAROON_SECRET_FILENAME=synapse-macaroon-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_MACAROON_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate form secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_FORM_SECRET_FILENAME=synapse-form-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_FORM_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate MAS secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_MAS_SECRET_FILENAME=synapse-mas-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_MAS_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate all static secrets"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
mkdir -p "${keys_dir}"

generate_if_missing() {
  target="$1"
  if [ -s "${target}" ]; then
    echo "Secret already exists: ${target}"
    return 0
  fi
  umask 027
  openssl rand -hex 32 >"${target}"
  chmod 640 "${target}"
  echo "Generated secret: ${target}"
}

generate_if_missing "${keys_dir}/synapse-registration-secret.txt"
generate_if_missing "${keys_dir}/synapse-macaroon-secret.txt"
generate_if_missing "${keys_dir}/synapse-form-secret.txt"
generate_if_missing "${keys_dir}/synapse-mas-secret.txt"

#@group "Synapse signing key"

#@step "Regenerate Synapse signing key"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_SIGNING_KEY_FILENAME=synapse-signing.key
#@env SYNAPSE_CONTAINER=synapse
#@env SYNAPSE_IMAGE=matrixdotorg/synapse:latest
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
signing_key_filename="${SYNAPSE_SIGNING_KEY_FILENAME}"
container_name="${SYNAPSE_CONTAINER-}"
synapse_image="${SYNAPSE_IMAGE}"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

mkdir -p "${keys_dir}"
new_key_file="${tmpdir}/new_signing.key"

echo "Generating new Synapse signing key from container: ${container_name}"
if docker exec "${container_name}" python3 -m synapse._scripts.generate_signing_key -o /tmp/new_signing.key 2>/dev/null; then
  docker cp "${container_name}:/tmp/new_signing.key" "${new_key_file}"
  docker exec "${container_name}" rm -f /tmp/new_signing.key >/dev/null 2>&1 || true
else
  echo "Container exec failed. Falling back to image: ${synapse_image}" >&2
  docker run --rm "${synapse_image}" python3 -m synapse._scripts.generate_signing_key -o - >"${new_key_file}"
fi

if [ ! -s "${new_key_file}" ]; then
  echo "Failed to generate signing key." >&2
  exit 1
fi

key_id="$(awk 'NR==1 {print $2}' "${new_key_file}")"
if [ -z "${key_id}" ]; then
  echo "Could not extract key ID from generated key." >&2
  exit 1
fi

new_key_host_path="${keys_dir}/${signing_key_filename}"
new_key_config_path="/data/keys/${signing_key_filename}"

if [ -f "${new_key_host_path}" ]; then
  old_key_backup="${keys_dir}/old_${signing_key_filename}.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "${new_key_host_path}" "${old_key_backup}"
  echo "Backed up old signing key: ${old_key_backup}"
fi

cp -a "${new_key_file}" "${new_key_host_path}"
chmod 640 "${new_key_host_path}"
echo "Wrote new signing key: ${new_key_host_path}"
echo "New signing key path: ${new_key_config_path}"
echo "Generated key id: ${key_id}"

#@group "Synapse storage provider"

#@step "Install Synapse S3 storage provider in running container"
#@env SYNAPSE_CONTAINER=synapse
#@env SYNAPSE_S3_PROVIDER_PATH=/opt/synapse-s3-storage-provider
set -euo pipefail

container_name="${SYNAPSE_CONTAINER}"
provider_path="${SYNAPSE_S3_PROVIDER_PATH}"

if ! docker ps --format '{{.Names}}' | grep -Fxq "${container_name}"; then
  echo "Container '${container_name}' is not running. Start Synapse first."
  exit 1
fi

docker exec "${container_name}" python3 -m pip install "${provider_path}"
echo "Installed Synapse S3 storage provider from ${provider_path} in ${container_name}"
