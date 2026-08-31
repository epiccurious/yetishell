#!/bin/bash
#
# development script to generate a 3-of-7 multisig nd burn 7 discs
# with one private key, the descriptor, and a README.txt per disc
# start under the assumption that Bitcoin Core is running and
# the system is airgapped

BITCOIN_DATA_DIRECTORY="${HOME}/.bitcoin"

echo 'Checking the RPC status.'
BITCOIN_RPC_TIMEOUT_SECONDS=300
if ! bitcoin-cli --datadir="${BITCOIN_DATA_DIRECTORY}" --rpcwait --rpcwaittimeout="${BITCOIN_RPC_TIMEOUT_SECONDS}" getrpcinfo > /dev/null; then
  throw_error "RPC communication failed after ${BITCOIN_RPC_TIMEOUT_SECONDS} seconds."
fi

# TODO add a check that networking is disabled

sudo apt -qq update
sudo apt -qq install -y jq xorriso

## disable networking stack
## TODO uncomment this next line during QA release candidate testing
# nmcli networking off
## disable bluetooth comms
rfkill block bluetooth
## disable memory swap
sudo swapoff -a

for key_index in {1..7}; do
  bitcoin-cli createwallet "key_${key_index}"
done

declare -A xpubs
for xpub_index in {1..7}; do
  xpubs["xpub_${xpub_index}"]=$(
    bitcoin-cli -rpcwallet="key_${xpub_index}" listdescriptors |
      jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' |
      awk -F '[()]' '{print $2}'
  )
done
# alternate parse without grep is:
# | .desc' | sed -n 's/.*(\([^)]*\)).*/\1/p')
# or with grep -E is:
# | .desc' | grep -Eo '\([^)]*\)' | sed 's/[()]//g')
# standard way is:
# | .desc' | grep -Po '(?<=\().*(?=\))' | sed 's /0/\* /<0;1>/* ')

echo 'Building the descriptor.'
desc="wsh(sortedmulti(3,${xpubs["xpub_1"]},${xpubs["xpub_2"]},${xpubs["xpub_3"]},${xpubs["xpub_4"]},${xpubs["xpub_5"]},${xpubs["xpub_6"]},${xpubs["xpub_7"]}))"
echo 'Getting the descriptor checksum.'
checksum=$(bitcoin-cli getdescriptorinfo "${desc}" | jq -r '.checksum')
echo 'Generating importable JSON including descriptor with checksum and metadata flags.'
multisig_desc="[{\"desc\": \"${desc}#${checksum}\", \"active\": true, \"timestamp\": \"now\"}]"
echo 'Creating multisig watch-only wallet.'
bitcoin-cli -named createwallet "multisig_watch_wallet" true true
echo 'Importing JSON descriptor into multisig watch-only wallet.'
bitcoin-cli -rpcwallet="multisig_watch_wallet" importdescriptors "${multisig_desc}"
echo 'Printing wallet metadata for the multisig watch-only wallet.'
bitcoin-cli -rpcwallet="multisig_watch_wallet" getwalletinfo

echo 'All wallet files are created.'
echo 'Beginning the DVD burning process.'

readonly DEFAULT_CDROM='/dev/cdrom'
until [ -f "${DEFAULT_CDROM}" ]; do echo 'DVD writer not found. Please connect your DVD writer via USB' && sleep 5; done
DVD_WRITER_DEVICE="$(readlink -f "${DEFAULT_CDROM}")"
/usr/lib/udev/cdrom_id --lock-media /dev/sr0 | grep -Fq 'ID_CDROM_DVD_PLUS_R=1' ||
  throw_error "The CD drive ${DVD_WRITER_DEVICE} does not have the DVD+R burning capability."
# TODO check look if /dev/sr1 exists and do the same check for that drive
# TODO (continued) only throw error is both sr0 and sr1 lack DVD capability
readonly DVD_WRITER_DEVICE

cd "${BITCOIN_DATA_DIRECTORY}/" ||
  throw_error "Unable to access ${BITCOIN_DATA_DIRECTORY}/."

for dvd_index in {1..7}; do
  echo "Generating ISO for Archive DVD ${dvd_index}."
  # generate an iso with a title of ARCHIVE_00${cd_index} and containing key_${cd_index} and multisig_watch_wallet
  # xorisso -o archive_00${cd_index}.iso key_1/* multisig_watch_wallet/*
  eject "${DVD_WRITER_DEVICE}"
  read -r -p "Press insert Archive DVD ${dvd_index} then press ENTER to continue..."
  echo 'Checking if disc is burnable.'
  # check if disk status: " is blank"
  echo "Burning ISO for Archive DVD ${dvd_index} to disc."
  # xorisso -as cdwriter ...
  echo "Please remove Archive DVD ${dvd_index}."
done
eject "${DVD_WRITER_DEVICE}"

read -r -p "Finished burning all of the Archive DVDs. Press ENTER to continue..."
