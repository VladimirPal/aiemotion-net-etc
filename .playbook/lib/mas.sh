#!/usr/bin/env bash

. ".playbook/lib/base.sh"

mas_generate_secret_if_missing() {
  keys_dir="$1"
  filename="$2"
  target="${keys_dir}/${filename}"

  need mkdir || return 1
  need openssl || return 1
  need chmod || return 1

  mkdir -p "${keys_dir}"
  if [ -s "${target}" ]; then
    echo "Secret already exists: ${target}"
    return 0
  fi

  umask 027
  openssl rand -hex 32 >"${target}"
  chmod 640 "${target}"
  echo "Generated secret: ${target}"
}

mas_generate_oidc_signing_keys() {
  keys_dir="$1"
  config_path="$2"
  mas_image="$3"
  if [ -z "${mas_image}" ]; then
    mas_image="ghcr.io/element-hq/matrix-authentication-service:latest"
  fi

  need docker || return 1
  need grep || return 1
  need date || return 1
  need mktemp || return 1
  need mkdir || return 1
  need cp || return 1
  need awk || return 1
  need chmod || return 1
  need rm || return 1

  if [ ! -f "${config_path}" ]; then
    echo "Config not found: ${config_path}" >&2
    return 1
  fi

  mkdir -p "${keys_dir}"
  tmpdir="$(mktemp -d)"

  generated_cfg="${tmpdir}/generated.yaml"
  echo "Generating fresh MAS config (for new keys) using image: ${mas_image}"
  if ! docker run --rm --entrypoint mas-cli "${mas_image}" config generate >"${generated_cfg}"; then
    /bin/rm -rf "${tmpdir}"
    return 1
  fi

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_dir="${keys_dir}/backup-oidc-${timestamp}"
  had_existing="false"
  for name in oidc-rsa.pem oidc-ec-p256.pem oidc-ec-p384.pem oidc-ec-secp256k1.pem; do
    key_path="${keys_dir}/${name}"
    if [ -s "${key_path}" ]; then
      mkdir -p "${backup_dir}"
      cp -a "${key_path}" "${backup_dir}/${name}"
      had_existing="true"
    fi
  done

  if [ "${had_existing}" = "true" ]; then
    echo "Backed up existing OIDC keys to: ${backup_dir}"
  fi

  for name in oidc-rsa.pem oidc-ec-p256.pem oidc-ec-p384.pem oidc-ec-secp256k1.pem; do
    /bin/rm -f "${keys_dir}/${name}" 2>/dev/null || true
  done

  awk -v outdir="${keys_dir}" '
    BEGIN { state = 0; ec = 0; }
    /-----BEGIN RSA PRIVATE KEY-----/ {
      out = outdir "/oidc-rsa.pem";
      print "-----BEGIN RSA PRIVATE KEY-----" > out;
      state = 1;
      next;
    }
    /-----BEGIN EC PRIVATE KEY-----/ {
      ec++;
      if (ec == 1) out = outdir "/oidc-ec-p256.pem";
      else if (ec == 2) out = outdir "/oidc-ec-p384.pem";
      else if (ec == 3) out = outdir "/oidc-ec-secp256k1.pem";
      else out = outdir "/oidc-ec-" ec ".pem";
      print "-----BEGIN EC PRIVATE KEY-----" > out;
      state = 1;
      next;
    }
    state == 1 {
      gsub(/^[[:space:]]+/, "", $0);
      gsub(/^['\''"]+/, "", $0);
      gsub(/['\''"]+$/, "", $0);
      if ($0 ~ /-----END/) {
        print $0 >> out;
        close(out);
        state = 0;
      } else if ($0 != "") {
        print $0 >> out;
      }
    }
  ' "${generated_cfg}"

  for name in oidc-rsa.pem oidc-ec-p256.pem oidc-ec-p384.pem oidc-ec-secp256k1.pem; do
    if [ -f "${keys_dir}/${name}" ]; then
      chmod 640 "${keys_dir}/${name}" 2>/dev/null || true
    fi
  done

  if [ ! -s "${keys_dir}/oidc-rsa.pem" ]; then
    /bin/rm -rf "${tmpdir}"
    echo "Failed to extract OIDC RSA key to ${keys_dir}/oidc-rsa.pem" >&2
    return 1
  fi

  /bin/rm -rf "${tmpdir}"
  echo "Generated OIDC key files in: ${keys_dir}"
  echo "Configured MAS key references in ${config_path} should point to /keys/oidc-*.pem"
}
