#
# af-dsutil.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Wrapper around the ROOT macro to manage datasets.
#

# Source environment for AF and AliEn + ROOT
source /etc/aafrc || exit 1
source "$AF_PREFIX/etc/env-alice.sh" --root current || exit 1

#
# Parse options
#

Prog=$(basename "$0")

Args=$(getopt -o 'n' --long 'no-token' -n"$Prog" -- "$@")
[ $? != 0 ] && exit 1

eval set -- "$Args"

while [ "$1" != "--" ] ; do

  case "$1" in

    --no-token)
      CreateToken=0
      shift 1
    ;;

    *)
      # Should never happen
      echo "Ignoring unknown option: $1"
      shift 1
    ;;

  esac

done

shift # --

if [ "$CreateToken" != 0 ] ; then
  source "$AF_PREFIX/etc/af-alien-lib.sh"
  AutoAuth
fi

# Starting ROOT: exit code is preserved
root -l -b "$AF_PREFIX/libexec/afdsutil.C+" "$@"
exit $?
