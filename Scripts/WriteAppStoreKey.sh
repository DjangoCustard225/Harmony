#!/usr/bin/env bash
# Writes the App Store Connect API key (.p8) to the given path as a clean PEM file.
# The key is read from APP_STORE_CONNECT_PRIVATE_KEY, however its line breaks were stored:
# normal PEM, one line, literal "\n", Windows line endings, a bare key body, or base64 of a PEM.
set -euo pipefail

output="${1:?usage: WriteAppStoreKey.sh <output-path>}"
raw="${APP_STORE_CONNECT_PRIVATE_KEY:?APP_STORE_CONNECT_PRIVATE_KEY is empty}"

case "$raw" in
*BEGIN*) ;;
*)
    decoded=$(printf '%s' "$raw" | base64 --decode 2>/dev/null || true)
    case "$decoded" in *BEGIN*) raw="$decoded" ;; esac
    ;;
esac

body=$(printf '%s' "$raw" | sed -e 's/\\n/ /g' | tr -d '\r' \
    | sed -e 's/-----BEGIN PRIVATE KEY-----//' -e 's/-----END PRIVATE KEY-----//' | tr -d ' \n\t')
{
    echo "-----BEGIN PRIVATE KEY-----"
    printf '%s' "$body" | fold -w 64
    echo
    echo "-----END PRIVATE KEY-----"
} >"$output"
chmod 600 "$output"

# Non-secret facts only. A P-256 .p8 body is 180-210 characters and begins "MIGHAgEAMBMG" or "MIGTAgEAMBMG".
case "$body" in MIG[HT]AgEAMBMGByqGSM49*) looks=yes ;; *) looks=no ;; esac
echo "API key: ${#body} body characters, begins like a P-256 key: $looks"

if ! openssl pkey -in "$output" -noout 2>/dev/null; then
    rm -f "$output"
    echo "error: the App Store Connect API key could not be read as a PEM private key." >&2
    echo "Copy the whole .p8 file, including the BEGIN and END lines, into the secret." >&2
    exit 1
fi
