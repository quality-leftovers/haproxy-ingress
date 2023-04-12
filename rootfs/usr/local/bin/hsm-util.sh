#!/bin/bash
# Simple HSM utility for SFH.
# Depends on openssl and p11tool for most operations to be installed.
#
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

DEFAULT_TOKEN_LABEL="p11prov"

set -eu -o pipefail

function printHelp() {
  echo "\

SYNOPSIS
  sfh-hsm-util [OPTION]... [ARGUMENT]

ARGUMENTS
   pkcs11                            : PKCS#11 Commands
            [list-tokens]            : List all tokens
            [list-objects]           : List all objects
            [export-privkey]         : URI to PEM
   x509                              : Some x509 commands
            [self-signed-cert]       : Create a self signed certificate

OPTIONS
   -u|--uri            : URI for the command
   -o|--out            : Output file path for the command
   --login          : Perform an optional login, if possible (e.g. C_Login)
   --include-pin    : Include pin in key PEM
   --pkcs11-so-path : Set PKCS11 module (.so) path
   -n|--name        : Set (common) name
   --add-san-dns    : Add a SAN
"
}


URI=""
OUT=""
POSITIONAL_ARGS=()
ARGUMENT=""
ARGUMENT2=""
LOGIN=0
NAME=""
X509_SUBJECT_ALTERNATIVE_NAMES=()
PKCS11_SO_PATH="/usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so"
PKCS11_DEFAULT_TOKEN_LABEL="sfh"

function die() {
  echo "$@" 1>&2; exit 1
}

function formatOptionError() {
  if [[ -z "${2-}" ]]; then
    echo "Option $1 is not set"
  else
    echo "Option $1 is not set ($2)";
  fi
}

function getDefaultTokenUri() {
  p11tool --provider /usr/lib/x86_64-linux-gnu/pkcs11/p11-kit-client.so --list-token-urls | grep "token=$DEFAULT_TOKEN_LABEL" | head -1 || exit "Failed to get default token URI"
}

function checkUriOption() {
  [ ! -z "$URI" ] || die $(formatOptionError "uri" "$@")
}
function checkNameOption() {
  [ ! -z "$NAME" ] || die $(formatOptionError "name" "$@")
}
function checkOutOption() {
  [ ! -z "$OUT" ] || die $(formatOptionError "out" "$@")
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--uri)
      URI="$2"
      shift
      shift
      ;;
    -n|--name)
      NAME="$2"
      shift
      shift
      ;;
    --add-san-dns)
      X509_SUBJECT_ALTERNATIVE_NAMES+=("DNS:$2")
      shift
      shift
      ;;
    -o|--out)
      OUT="$2"
      shift
      shift
      ;;
    --login)
      LOGIN=1
      shift
      ;;
    --pkcs11-so-path)
       PKCS11_SO_PATH="$2"
       shift;
       shift;
       ;;
    --*)
      die "Unknown switch $1"
      ;;
    *)
      if [ -z "$ARGUMENT" ]; then
          ARGUMENT="$1"
      elif [ -z "$ARGUMENT2" ]; then
          ARGUMENT2="$1"
      fi
      shift # past argument
      ;;
  esac
done


function pkcs11Cmd() {
  case "$ARGUMENT2" in
    "list-tokens")
      set -x
      p11tool --provider "$PKCS11_SO_PATH" --list-token-urls
      set +x
      ;;
    "list-objects")
      if [[ -z "$URI" ]]; then
        echo "Trying to get default token"
        set -x
        tokens=$(p11tool --provider "$PKCS11_SO_PATH" --list-token-urls)
        set +x
        URI=$(echo "$tokens" | grep "token=$PKCS11_DEFAULT_TOKEN_LABEL" | head -1)
      fi
      opt=()
      if [ $LOGIN -eq 1 ]; then
        opt+=("--login")
      fi
      set -x
      p11tool --provider "$PKCS11_SO_PATH" --list-all "${opt[@]}" "$URI" || die "invoking p11tool failed"
      set +x
      ;;
    "export-privkey")
      checkUriOption
      opt=()
      if [ ! -z "$OUT" ]; then
         opt+=("-out")
         opt+=("$OUT")
      fi
      set -x
      openssl pkey -in "$URI" -outform PEM "${opt[@]}" || die "invoking openssl failed"
      set +x
    ;;
    *)
      printHelp
      die "No argument was set"
      ;;
  esac
}

function x509Cmd() {
  case "$ARGUMENT2" in
    "self-signed-cert")
      checkUriOption
      checkNameOption
      checkOutOption
      for san in "${X509_SUBJECT_ALTERNATIVE_NAMES[@]}"; do
        opt+=(-addext "subjectAltName = $san" )
      done
      set -x
      openssl req -x509 -key "$URI" -outform PEM -sha256 -subj "/C=DE/CN=$NAME" "${opt[@]}" -out "$OUT" || die "invoking openssl failed"
      set +x
      ;;
    *)
      printHelp
      die "Argument $ARGUMENT2 not supported. Use one of [self-signed-cert]"
      ;;
  esac
}


case "$ARGUMENT" in
  "pkcs11")
    pkcs11Cmd
    ;;
  "x509")
    x509Cmd
    ;;
  *)
    printHelp
    die "Argument $ARGUMENT not supported. Use one of [x509|pkcs11]"
    ;;
esac
