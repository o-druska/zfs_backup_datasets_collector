#!/bin/sh
# This file is licensed under the ISC license.
# Anne Ghisla 2021
# sibling script of zfs_diff1_snapshots

readonly VERSION='0.0.1'
readonly SSH_CMD='ssh -o ConnectTimeout=10 -o BatchMode=yes'

BKP=''
BKP_DS=''
BKP_FOLDERS=''
BKP_SNAPS=''

# TODO: control timeout with flag

### FUNCTIONS
Fatal() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

Help() {
    cat << EOF
${0##*/} v${VERSION}

${0##*/} looks for leftover backups, i.e. from retired ZFS datasets.
Other routines delete the snapshots as they get older, but not the datasets
themselves.

WIP:
This script only lists the zombie datasets in the backups, doesn't act on them.
There is actually a time window just after the removal of the dataset from data1
(or wherever the live data sit), during which the backup is still needed,
in which case it will have one or more snaphots.
The working idea is to check if that dataset has at least one surviving snapshot.
If not, it's time for it to go.

(I'm leaving the same syntax for now, but this script won't need all options)

Syntax:
${0##*/} [ options ] [host:]zfs_dataset | file ...

OPTIONS:
  -h, --help        = Print this help and exit
  -V, --version     = Print the version number and exit

EXAMPLES:
  ${0##*/} hdd1/llamas
  ${0##*/} jimbo@backup.example.org:tank/llamas
  ${0##*/} backup_llamas.txt snapshots_backup_llamas.txt

EOF
}

RemoteDataset() {
    [ -z "${1%%*:*}" ] && return 0 || return 1
}
DatasetExists() {
    zfs list -H -o name "$1" > /dev/null 2>&1 && return 0 || return 1
}


#TODO: rewrite this case as:
# - if there are two arguments and they are not both files, complain
# - if there is one argument and it's a file, complain
# I'll blindly edit the code from now on

case "$1" in
    '-h'|'--help'|'')
        Help; exit 0;;
    '-V'|'--version')
        printf '%s v%s\n' "${0##*/}" "${VERSION}"; exit 0;;
    -*)
        Fatal "'$1' is not a valid option. See ${0##*/} --help for usage";;
    *)
        [ -z "$2" ] && Fatal "${0##*/} requires two targets to diff."
        [ -z "$3" ] || Fatal "${0##*/} accepts only two targets to diff."
        BKP=$1
        #TODO: assign it as needed
        # BKP_SNAPHOTS=$2
        ;;
esac

# create tmp dir
TMPDIR=`mktemp -d` || Fatal "Unable to create tmp dir."

#
# backup datasets and snapshots
#
if [ -f "$BKP" ]; then
    # not sure if "folders" is good, just sed it with the better concept later
    BKP_FOLDERS=$(cat "$BKP") || exit 1
elif RemoteDataset "$BKP"; then
    BKP_HOST=${BKP%%:*}
    BKP_DS=${BKP#*:}
    BKP_FOLDERS=$($SSH_CMD $BKP_HOST "zfs list -H -o name -r '$BKP_DS'") || exit 1
    BKP_SNAPS=$($SSH_CMD $BKP_HOST "zfs list -t snapshot -H -o name -r '$BKP_DS'") || exit 1
elif DatasetExists "$BKP"; then
    BKP_DS=${BKP}
    BKP_FOLDERS=$(zfs list -H -o name -r "$BKP_DS") || exit 1
    BKP_SNAPS=$(zfs list -t snapshot -H -o name -r "$BKP_DS") || exit 1
else
    Fatal "'$BKP' is not a valid file nor ZFS dataset."
fi

[ -z "$BKP_FOLDERS" ] && Fatal "$BKP has no ... folders"

#
# backup snapshots from a file (only in case of two-argument-input)
#

#TODO: check that the first argument was a file - otherwise it gets confusing
# (if the first argument is not a file, reading a file brings new information
# from potentially unrelated datasets)
if [ -f "$BKP_SNAPS_FILE" ]; then
    BKP_SNAPS=$(cat "$BKP_SNAPS_FILE") || exit 1
else
    Fatal "'$BKP_SNAPS_FILE' is not a valid file."
fi

[ -z "$BKP_SNAPS" ] && Fatal "$BKP has no snapshots"

#
# compare datasets and snapshots
#

printf "$BKP_FOLDERS" | sort > "${TMPDIR}/folders"
# cut each line before the @, keep only unique lines
printf "$BKP_SNAPS" | cut -f1 -d"@" | uniq  | sort > "${TMPDIR}/snaps"
comm -23 "${TMPDIR}/folders" "${TMPDIR}/snaps"

#
# cleanup
#
rm "${TMPDIR}/folders"
rm "${TMPDIR}/snaps"
rmdir "${TMPDIR}"
