#!/bin/bash
#
# Yeti multisig written in bash

set -o errexit
set -o nounset

check_internet_status()
{
  echo 'Checking for internet.'
  ( (check_internet_to_address 1.1.1.1 ||
    check_internet_to_address 1.1.0.0 ||
    check_internet_to_address 9.9.9.9 ||
    check_internet_to_address 9.9.9.11) &&
    check_internet_to_address bitcoincore.org) ||
    throw_error 'Internet checks failed.'
  echo 'Internet checks passed.'
}

check_internet_to_address()
{
  check_internet_address="$1"
  CHECK_INTERNET_PORT='443'
  CHECK_INTERNET_TIMEOUT_SECONDS='10'
  wget --quiet --no-check-certificate \
    --output-document=/dev/null \
    --tries=5 \
    --timeout="${CHECK_INTERNET_TIMEOUT_SECONDS}" \
    "https://${check_internet_address}:${CHECK_INTERNET_PORT}"
}

bitcoin_tarball_download()
{
  echo 'Downloading Bitcoin Core.'
  wget --tries=5 --quiet -O "${BITCOIN_HASH_FILE}" "${BITCOIN_HASH_FILE_SOURCE}"
  wget --tries 5 --quiet -O "${GPG_SIGNATURES_FILE}" "${GPG_SIGNATURES_FILE_SOURCE}"
  wget --tries 5 --quiet -O "${BITCOIN_TARBALL_TEMPORARY_PATH}" "${BITCOIN_TARBALL_FILE_SOURCE}"
}

bitcoin_tarball_download_and_validate()
{
  BITCOIN_SOURCE="https://bitcoincore.org/bin/bitcoin-core-${TARGET_BITCOIN_VERSION}"
  BITCOIN_TARBALL_FILE_SOURCE="${BITCOIN_SOURCE}/${BITCOIN_TARBALL_FILENAME}"
  BITCOIN_HASH_FILENAME='SHA256SUMS'
  BITCOIN_HASH_FILE_SOURCE="${BITCOIN_SOURCE}/${BITCOIN_HASH_FILENAME}"
  GPG_SIGNATURES_FILENAME='SHA256SUMS.asc'
  GPG_SIGNATURES_FILE_SOURCE="${BITCOIN_SOURCE}/${GPG_SIGNATURES_FILENAME}"
  GUIX_SIGS_REPO='https://github.com/bitcoin-core/guix.sigs'
  BITCOIN_TARBALL_TEMPORARY_PATH="${TEMP_DIRECTORY}/${BITCOIN_TARBALL_FILENAME}"
  BITCOIN_HASH_FILE="${TEMP_DIRECTORY}/${BITCOIN_HASH_FILENAME}"
  GPG_SIGNATURES_FILE="${TEMP_DIRECTORY}/${GPG_SIGNATURES_FILENAME}"
  GUIX_SIGS_TEMPORARY_DIRECTORY="${TEMP_DIRECTORY}/guix.sigs"
  GUIX_SIGS_DESTINATION_DIRECTORY="${HOME}/Downloads/guix.sigs"

  bitcoin_tarball_download
  bitcoin_tarball_validate_checksum
  bitcoin_tarball_validate_signatures
  
  # move the tarball to the user's Downloads directory only after
  # validating the sha256 hash and GPG signatures
  move_tarball_and_guix_sigs_from_temp_directory_to_downloads
  [ -f "${BITCOIN_HASH_FILE}" ] && rm "${BITCOIN_HASH_FILE}"
  [ -f "${GPG_SIGNATURES_FILE}" ] && rm "${GPG_SIGNATURES_FILE}"
}

bitcoin_tarball_download_extract_test_install()
{
  BITCOIN_CORE_EXTRACT_DIR="${TEMP_DIRECTORY}/bitcoin-core"
  BITCOIN_INSTALL_BIN_SOURCE="${BITCOIN_CORE_EXTRACT_DIR}/bin"
  BITCOIN_INSTALL_LIB_SOURCE="${BITCOIN_CORE_EXTRACT_DIR}/lib"
  BITCOIN_INSTALL_LIBEXEC_SOURCE="${BITCOIN_CORE_EXTRACT_DIR}/libexec"
  BITCOIN_INSTALL_INCLUDE_SOURCE="${BITCOIN_CORE_EXTRACT_DIR}/include"
  BITCOIN_INSTALL_MAN_SOURCE="${BITCOIN_CORE_EXTRACT_DIR}/share/man/man1"
  BITCOIN_INSTALL_DESTINATION='/usr/local'
  BITCOIN_INSTALL_BIN_DESTINATION="${BITCOIN_INSTALL_DESTINATION}/bin"
  BITCOIN_INSTALL_LIB_DESTINATION="${BITCOIN_INSTALL_DESTINATION}/lib"
  BITCOIN_INSTALL_INCLUDE_DESTINATION="${BITCOIN_INSTALL_DESTINATION}/include"
  BITCOIN_INSTALL_MAN_DESTINATION="${BITCOIN_INSTALL_DESTINATION}/share/man/man1"

  BITCOIN_TARBALL_FILENAME="bitcoin-${TARGET_BITCOIN_VERSION}-${TARGET_ARCHITECTURE}-${TARGET_BITCOIN_TARBALL_OS}.tar.gz"
  BITCOIN_TARBALL_DESTINATION_PATH="${HOME}/Downloads/${BITCOIN_TARBALL_FILENAME}"

  [ -f "${BITCOIN_TARBALL_DESTINATION_PATH}" ] || bitcoin_tarball_download_and_validate
  bitcoin_tarball_extract
  bitcoin_tarball_test
  bitcoin_tarball_install

  echo 'Removing installation files.'
  rm -r "${BITCOIN_CORE_EXTRACT_DIR:?}/"
  rm -r "${TEMP_DIRECTORY:?}/"
  echo 'Bitcoin Core installation complete.'
}

bitcoin_tarball_extract()
{
  echo 'Extracting Bitcoin Core.'
  [ -d "${BITCOIN_CORE_EXTRACT_DIR}"/ ] || mkdir "${BITCOIN_CORE_EXTRACT_DIR}"
  tar -xzf "${BITCOIN_TARBALL_DESTINATION_PATH}" -C "${BITCOIN_CORE_EXTRACT_DIR}"/ --strip-components=1
}

bitcoin_tarball_install()
{
  echo "Installing Bitcoin Core ${TARGET_BITCOIN_VERSION}."
  # install the libraries
  if [ -d "${BITCOIN_INSTALL_LIB_SOURCE}" ]; then
    [ -d "${BITCOIN_INSTALL_LIB_DESTINATION}" ] ||
      mkdir -p "${BITCOIN_INSTALL_LIB_DESTINATION}" 2> /dev/null ||
      sudo mkdir "${BITCOIN_INSTALL_LIB_DESTINATION}" ||
      throw_error "Unable to create directory ${BITCOIN_INSTALL_LIB_DESTINATION}."
    
    sudo cp \
      "${BITCOIN_INSTALL_LIB_SOURCE}/libbitcoinconsensus.so.0.0.0" \
      "${BITCOIN_INSTALL_LIB_DESTINATION}/libbitcoinconsensus.so.0.0.0"
    (cd "${BITCOIN_INSTALL_LIB_DESTINATION}"/ && {
      sudo ln -s -f libbitcoinconsensus.so.0.0.0 libbitcoinconsensus.so.0 || {
        sudo rm -f libbitcoinconsensus.so.0
        sudo ln -s libbitcoinconsensus.so.0.0.0 libbitcoinconsensus.so.0
      }
    })
    (cd "${BITCOIN_INSTALL_LIB_DESTINATION}"/ && {
      sudo ln -s -f libbitcoinconsensus.so.0.0.0 libbitcoinconsensus.so || {
        sudo rm -f libbitcoinconsensus.so
        sudo ln -s libbitcoinconsensus.so.0.0.0 libbitcoinconsensus.so
      }
    })
    PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin:/sbin' \
      ldconfig -n "${BITCOIN_INSTALL_LIB_DESTINATION}"
  fi

  # install the binaries
  [ -d "${BITCOIN_INSTALL_BIN_DESTINATION}" ] ||
    mkdir -p "${BITCOIN_INSTALL_BIN_DESTINATION}" 2> /dev/null ||
    sudo mkdir "${BITCOIN_INSTALL_BIN_DESTINATION}" ||
    throw_error "Unable to create directory ${BITCOIN_INSTALL_BIN_DESTINATION}."
  for bitcoin_executable in bitcoind bitcoin-qt bitcoin-cli bitcoin-tx bitcoin-util bitcoin-wallet; do
    sudo install -c \
      "${BITCOIN_INSTALL_BIN_SOURCE}/${bitcoin_executable}" \
      "${BITCOIN_INSTALL_BIN_DESTINATION}/"
  done

  # install the header files
  if [ -d "${BITCOIN_INSTALL_INCLUDE_SOURCE}" ]; then
    [ -d "${BITCOIN_INSTALL_INCLUDE_DESTINATION}" ] ||
      mkdir -p "${BITCOIN_INSTALL_INCLUDE_DESTINATION}" 2> /dev/null ||
      sudo mkdir "${BITCOIN_INSTALL_INCLUDE_DESTINATION}" ||
      throw_error "Unable to create directory ${BITCOIN_INSTALL_INCLUDE_DESTINATION}."
    sudo install -c -m 644 \
      "${BITCOIN_INSTALL_INCLUDE_SOURCE}/bitcoinconsensus.h" \
      "${BITCOIN_INSTALL_INCLUDE_DESTINATION}/"
  fi

  # install the binary man pages
  [ -d "${BITCOIN_INSTALL_MAN_DESTINATION}" ] ||
    mkdir -p "${BITCOIN_INSTALL_MAN_DESTINATION}" 2> /dev/null ||
    sudo mkdir -p "${BITCOIN_INSTALL_MAN_DESTINATION}" ||
    throw_error "Unable to create directory ${BITCOIN_INSTALL_MAN_DESTINATION}."
  for man_page in bitcoind.1 bitcoin-qt.1 bitcoin-cli.1 bitcoin-tx.1 bitcoin-util.1 bitcoin-wallet.1; do
    sudo install -c -m 644 "${BITCOIN_INSTALL_MAN_SOURCE}/${man_page}" "${BITCOIN_INSTALL_MAN_DESTINATION}/"
  done
}

bitcoin_tarball_test()
{
  echo 'Running the unit tests.'
  case "$("${BITCOIN_INSTALL_LIBEXEC_SOURCE}"/test_bitcoin 2>&1)" in
    *'No errors detected'*) ;;
    *)
      printf '\n%s\n' "${UNIT_TEST_RESPONSE}"
      throw_error 'Unit tests failed.'
      ;;
  esac
}

bitcoin_tarball_validate_signatures()
{
  GPG_GOOD_SIGNATURES_REQUIRED='7'
  GPG_GOOD_SIGNATURE_COUNT="$(bitcoin_tarball_validate_count_signatures)"
  if [ "${GPG_GOOD_SIGNATURE_COUNT}" -lt "${GPG_GOOD_SIGNATURES_REQUIRED}" ]; then
    throw_error "INVALID SIGNATURES. The download has failed. This script cannot continue due to security concerns. Please review the temporary file ${TEMP_DIRECTORY}/${GPG_SIGNATURES_FILE}."
  fi
  echo "Found ${GPG_GOOD_SIGNATURE_COUNT} good signatures."
}

bitcoin_tarball_validate_checksum()
{
  cd "${TEMP_DIRECTORY}"/
  SHA256_CHECK="$(grep "${BITCOIN_TARBALL_FILENAME}" "${BITCOIN_HASH_FILENAME}" | sha256sum --check 2> /dev/null)"
  cd - > /dev/null

  case "${SHA256_CHECK}" in
    *'OK'*) 
      echo 'Validated the checksum.'
      ;;
    *)
      throw_error "INVALID CHECKSUM. The download has failed. This script cannot continue due to security concerns. Please review the temporary file ${TEMP_DIRECTORY}/${BITCOIN_HASH_FILE}."
      ;;
  esac
}

bitcoin_tarball_validate_count_signatures()
{
  [ -d "${GUIX_SIGS_DESTINATION_DIRECTORY}"/ ] ||
    git clone --depth 1 --quiet "${GUIX_SIGS_REPO}.git" "${GUIX_SIGS_TEMPORARY_DIRECTORY}"
  gpg --quiet --import "${GUIX_SIGS_TEMPORARY_DIRECTORY}"/builder-keys/*.gpg

  SIGNATURE_COUNT="$(gpg --verify "${GPG_SIGNATURES_FILE}" 2>&1 | grep -c '^gpg: Good signature from ')" &&
    readonly SIGNATURE_COUNT
  pgrep '^gpg-agent$' > /dev/null && gpgconf --kill gpg-agent
  pgrep '^keyboxd$' > /dev/null && gpgconf --kill keyboxd
  printf '%s\n' "${SIGNATURE_COUNT}"
}

move_tarball_and_guix_sigs_from_temp_directory_to_downloads() {
  [ -d "$(dirname "${BITCOIN_TARBALL_DESTINATION_PATH}")" ] ||
    mkdir -p "$(dirname "${BITCOIN_TARBALL_DESTINATION_PATH}")"
  mv "${BITCOIN_TARBALL_TEMPORARY_PATH}" "${BITCOIN_TARBALL_DESTINATION_PATH}"

  [ -d "${GUIX_SIGS_DESTINATION_DIRECTORY}/" ] ||
    mkdir -p "${GUIX_SIGS_DESTINATION_DIRECTORY}"
  mv "${GUIX_SIGS_TEMPORARY_DIRECTORY}" "${GUIX_SIGS_DESTINATION_DIRECTORY}"
}


throw_error() {
  [ -n "$1" ] &&
    echo "ERROR: $1"
  exit 1
}

install_runtime_dependencies() {
  sudo apt-get -qq update
  sudo DEBIAN_FRONTEND=noninteractive apt-get -qq install --assume-yes --no-install-recommends \
    git gnupg libxcb-xinerama0 \
    > /dev/null 2>&1
}

install_system_updates() {
  sudo apt-get -qq update
  sudo NEEDRESTART_MODE=a apt-get -qq full-upgrade --assume-yes 
}

TEMP_DIRECTORY="$(mktemp -d)"
TARGET_ARCHITECTURE="$(uname -m)"
TARGET_OS_RELEASE_ID='ubuntu'
TARGET_OS_VERSION_ID='26.04'
TARGET_BITCOIN_TARBALL_OS='linux-gnu'

TARGET_BITCOIN_VERSION='31.1'
BITCOIN_DATA_DIRECTORY="${HOME}/.bitcoin"
BITCOIN_CORE_CONFIG_FILE="${BITCOIN_DATA_DIRECTORY}/bitcoin.conf"

os_release_id="$(grep '^ID=' /etc/os-release | cut -d= -f2)"
os_version_id="$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2)"

if [ "${os_release_id}" != "${TARGET_OS_RELEASE_ID}" ] ||
  [ "${os_version_id}" != "${TARGET_OS_VERSION_ID}" ]; then
  throw_error "Must be running Ubuntu ${TARGET_OS_VERSION_ID}"
fi

check_internet_status
install_system_updates
install_runtime_dependencies
bitcoin_tarball_download_extract_test_install

[ -d "${BITCOIN_DATA_DIRECTORY}/" ] || mkdir "${BITCOIN_DATA_DIRECTORY}/"
echo "server=1" >> "${BITCOIN_CORE_CONFIG_FILE:?}"
echo "prune=200000" >> "${BITCOIN_CORE_CONFIG_FILE:?}"
# prune is set to 200 GiB
# TODO determine reasonable prune value or calculate it dynamically

setsid bitcoin-qt --datadir="${BITCOIN_DATA_DIRECTORY}" > /dev/null 2>&1 < /dev/null &

echo 'Checking the RPC status.'
BITCOIN_RPC_TIMEOUT_SECONDS=300
if ! bitcoin-cli --datadir="${BITCOIN_DATA_DIRECTORY}" --rpcwait --rpcwaittimeout="${BITCOIN_RPC_TIMEOUT_SECONDS}" getrpcinfo > /dev/null; then
  throw_error "RPC communication failed after ${BITCOIN_RPC_TIMEOUT_SECONDS} seconds."
fi

SLEEP_TIME_SECONDS='10'
blockchain_info=$(bitcoin-cli --datadir="${BITCOIN_DATA_DIRECTORY}" --rpcwait getblockchaininfo)
ibd_status=$(echo "${blockchain_info}" | jq '.initialblockdownload')

if [ ibd_status = 'true' ]; then
  sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
fi

while [ "${ibd_status}" = 'true' ]; do
  blocks=$(echo "${blockchain_info}" | jq '.blocks')
  headers=$(echo "${blockchain_info}" | jq '.headers')
  last_block_time=$(echo "${blockchain_info}" | jq '.time')
  size_on_disk_in_mib=$(($(echo "${blockchain_info}" | jq '.size_on_disk') / BYTES_TO_KIB / KIB_TO_MIB))
  sync_progress=$(echo "${blockchain_info}" | jq '.verificationprogress')

  # Handle case of early sync (e^-8 or e^-9) by replacing scientific notation with decimal percent
  case "${sync_progress}" in
    *e*) sync_progress_percent='0.0000001' ;;
    *) sync_progress_percent="$(awk -v prog="${sync_progress}" 'BEGIN{printf "%f\n", prog * 100}')" ;;
  esac

  free_space_in_mib="$(get_free_space_in_mib)"

  clear_the_terminal
  if [ "${headers}" -eq 0 ]; then
    log_info 'Pre-syncing the headers.'
    headers_presync_last_log_line="$(grep 'Pre-synchronizing blockheaders' "${BITCOIN_CORE_DEBUG_LOG_FILE}" | tail -1 || true)"
    if [ -n "${headers_presync_last_log_line}" ]; then
      headers_presync_progress_percent="$(echo "${headers_presync_last_log_line}" | cut -d~ -f2 | cut -d% -f1)"
    else
      headers_presync_progress_percent='0.0'
    fi
    printf 'Headers presync progress:   %.1f %%\n' "${headers_presync_progress_percent}"
  elif [ "${blocks}" -eq 0 ]; then
    log_info 'Re-syncing the headers.'
    headers_sync_last_log_line="$(grep 'Synchronizing blockheaders' "${BITCOIN_CORE_DEBUG_LOG_FILE}" | tail -1 || true)"
    if [ -n "${headers_sync_last_log_line}" ]; then
      headers_sync_progress_percent="$(echo "${headers_sync_last_log_line}" | cut -d~ -f2 | cut -d% -f1)"
    else
      headers_sync_progress_percent='0.0'
    fi
    printf 'Headers sync progress:      %.1f %%\n' "${headers_sync_progress_percent}"
  else
    log_info 'Syncing the blockchain. Please be patient.'
    printf 'Sync progress:              %.3f %%\n' "${sync_progress_percent}"
    printf 'Blocks remaining:           %d\n' "$((headers - blocks))"

    case "${TARGET_KERNEL}" in
      Darwin | FreeBSD | NetBSD | OpenBSD)
        current_chain_tip_timestamp="$(/bin/date -r "${last_block_time}" | cut -c 5-)"
        ;;
      *)
        current_chain_tip_timestamp="$(date -d @"${last_block_time}" | cut -c 5-)"
        ;;
    esac
    printf 'Current chain tip:          %s\n' "${current_chain_tip_timestamp}"

    printf '%s' 'Chain sync size:            '
    if [ "${size_on_disk_in_mib}" -gt "${MIB_TO_GIB}" ]; then
      printf '%d GiB\n' "$((size_on_disk_in_mib / MIB_TO_GIB))"
    else
      printf '%d MiB\n' "${size_on_disk_in_mib}"
    fi
  fi

  printf '%s' 'Disk free space:            '
  if [ "${free_space_in_mib}" -gt "${MIB_TO_GIB}" ]; then
    printf '%d GiB\n' "$((free_space_in_mib / MIB_TO_GIB))"
  else
    printf '%d MiB\n' "${free_space_in_mib}"
  fi

  printf '%s' "This info will refresh in ${SLEEP_TIME_SECONDS} seconds."
  sleep "${SLEEP_TIME_SECONDS}"

  blockchain_info=$(bitcoin-cli --datadir="${BITCOIN_DATA_DIRECTORY}" --rpcwait getblockchaininfo)
  printf '\n'
  ibd_status=$(echo "${blockchain_info}" | jq '.initialblockdownload')
done

echo "This script has completed successfully"
