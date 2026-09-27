#!/usr/bin/env bash
# Generate a shared root CA and per-cluster intermediate certs for Istio multi-primary.
# Usage: generate-certs.sh <certs_dir> <cluster1> <cluster2>
set -euo pipefail

CERTS_DIR="${1:?certs dir}"
C1="${2:-cluster1}"
C2="${3:-cluster2}"

mkdir -p "${CERTS_DIR}/${C1}" "${CERTS_DIR}/${C2}"

if [[ ! -f "${CERTS_DIR}/root-cert.pem" ]]; then
  openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:4096 \
    -subj "/O=Istio/CN=Root CA" \
    -keyout "${CERTS_DIR}/root-key.pem" \
    -out "${CERTS_DIR}/root-cert.pem"
fi

gen_intermediate() {
  local dir="$1"
  local cn="$2"
  if [[ -f "${dir}/ca-cert.pem" ]]; then
    return 0
  fi
  openssl req -newkey rsa:4096 -nodes \
    -keyout "${dir}/ca-key.pem" \
    -subj "/O=Istio/CN=${cn}" \
    -out "${dir}/cluster-ca.csr"
  cat > "${dir}/ca.cfg" <<EOF
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
subjectKeyIdentifier = hash
EOF
  openssl x509 -req -sha256 -days 3650 \
    -CA "${CERTS_DIR}/root-cert.pem" \
    -CAkey "${CERTS_DIR}/root-key.pem" \
    -CAcreateserial \
    -in "${dir}/cluster-ca.csr" \
    -out "${dir}/ca-cert.pem" \
    -extfile "${dir}/ca.cfg" \
    -extensions v3_req
  cp "${CERTS_DIR}/root-cert.pem" "${dir}/root-cert.pem"
  cat "${dir}/ca-cert.pem" "${CERTS_DIR}/root-cert.pem" > "${dir}/cert-chain.pem"
}

gen_intermediate "${CERTS_DIR}/${C1}" "Intermediate CA ${C1}"
gen_intermediate "${CERTS_DIR}/${C2}" "Intermediate CA ${C2}"

echo "Certs ready under ${CERTS_DIR}"
