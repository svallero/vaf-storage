#
# env-alice.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Sets the environment for ALICE software. Must be sourced, not run.
#

#
# Check if we are sourcing it or running it
#

if [ "$BASH_SOURCE" == "$0" ]; then
  echo 'You must source this file rather than running it. Try:' >&2
  echo "  source \"$0\"" >&2
  exit 1
fi

#
# Load AF configuration
#

source /etc/aafrc || return 1

#
# Requirements
#

if [ ! -r "$AF_DEP_FILE" ]; then
  echo 'Can not read dependency file, check AF_DEP_FILE variable' >&2
  return 1
fi

#
# Clean up useless variables and self
#

function CleanUp() {
  unset AliEnOnly AliRootVer Arch Args Dep Geant3Ver Prog RootVer Verbose
  unset CleanUp
}

#
# Parse options
#

Prog=$(basename "$BASH_SOURCE")

Args=$(getopt -o 'v' --long 'root:,alien,aliroot:,verbose' -n"$Prog" -- "$@")
if [ $? != 0 ]; then
  CleanUp
  return 1
fi

eval set -- "$Args"

while [ "$1" != "--" ] ; do

  case "$1" in

    --root)
      RootVer="$2"
      [ "$RootVer" == 'current' ] && RootVer=$(basename "$AF_ROOT_PROOF")
      shift 2
    ;;

    --aliroot)
      AliRootVer="$2"
      shift 2
    ;;

    --alien)
      AliEnOnly=1
      shift
    ;;

    --verbose|-v)
      Verbose=1
      shift
    ;;

    *)
      # Should never happen
      echo "Skipping unknown option: $1"
      shift 1
    ;;

  esac

done

shift # --

#while [ $# -gt 0 ] ; do
#  echo "ExtraArgument: $1"
#  shift 1
#done
#env|grep ^AF_

#
# List all the packages
#

if [ "$RootVer" == '' ] && [ "$AliRootVer" == '' ] && \
  [ "$AliEnOnly" != 1 ]; then

  echo ''

  echo 'Available AliRoot versions (and dependencies):'
  cat "$AF_DEP_FILE" | awk -F '[@:|]' \
    '{printf "  %s (ROOT: %s, Geant3: %s)\n", $4, $8, $12}'
  echo ''

  echo 'Available ROOT versions:'
  cat "$AF_DEP_FILE" | awk -F '[@:|]' '{printf "  %s\n", $8}' | sort -u
  echo ''

  echo 'Enable AliRoot with correct dependencies using:'
  echo "  source $Prog --aliroot VER"
  echo ''
  echo 'Enable the sole ROOT using:'
  echo "  source $Prog --root VER|\"current\""
  echo ''
  echo 'Enable the sole AliEn using:'
  echo "  source $Prog --alien"
  echo ''

  CleanUp
  return 1
fi

#
# Set variables for AliEn
#

if [ "$AF_ALIEN_DIR" == '' ]; then
  echo 'Environment variable AF_ALIEN_DIR not set, aborting' >&2
  CleanUp
  return 1
fi

# Certificates
export X509_CERT_DIR="$AF_ALIEN_DIR"/globus/share/certificates

# Paths
export PATH="$AF_ALIEN_DIR/bin:$AF_ALIEN_DIR/api/bin:$PATH"
export LD_LIBRARY_PATH="$AF_ALIEN_DIR/lib:$AF_ALIEN_DIR/api/lib:$LD_LIBRARY_PATH"

# Extra variables
export GSHELL_ROOT="$AF_ALIEN_DIR/api"

if [ "$AliEnOnly" == 1 ]; then
  [ "$Verbose" == 1 ] && echo 'AliEn environment set'
  CleanUp
  return 0
fi

#
# Find AliRoot dependencies (ROOT, Geant3)
#

if [ "$RootVer" == '' ]; then

  Dep=$(cat "$AF_DEP_FILE" | grep "VO_ALICE@AliRoot::$AliRootVer|" | head -n1)
  if [ "$Dep" == '' ]; then
    echo "AliRoot version $AliRootVer not found, aborting" >&2
    CleanUp
    return 1
  fi

  # Set RootVer and Geant3Ver properly
  eval $(echo "$Dep" | \
    awk -F '[@:|]' '{printf "RootVer=%s Geant3Ver=%s\n", $8, $12}')

fi

#
# Enable ROOT
#

export ROOTSYS="$AF_PACK_DIR"/VO_ALICE/ROOT/$RootVer/$RootVer
export PATH="$ROOTSYS/bin:$PATH"
export LD_LIBRARY_PATH="$ROOTSYS/lib:$LD_LIBRARY_PATH"

if [ "$AliRootVer" == '' ]; then
  [ "$Verbose" == 1 ] && echo "ROOT environment set ($RootVer)"
  CleanUp
  return 0
fi

Arch=$(root-config --arch)

#
# Enable Geant3
#

export GEANT3DIR="$AF_PACK_DIR"/VO_ALICE/GEANT3/$Geant3Ver/$Geant3Ver
export LD_LIBRARY_PATH="$GEANT3DIR/lib/tgt_$Arch:$LD_LIBRARY_PATH"

#
# Enable AliRoot
#

export ALICE_ROOT="$AF_PACK_DIR"/VO_ALICE/AliRoot/$AliRootVer/$AliRootVer
export PATH="$ALICE_ROOT/bin/tgt_$Arch:$PATH"
export LD_LIBRARY_PATH="$ALICE_ROOT/lib/tgt_$Arch:$LD_LIBRARY_PATH"

#
# The end
#

if [ "$Verbose" == 1 ]; then
  echo -n "AliRoot environment set "
  echo "(ROOT=$RootVer, Geant3=$Geant3Ver, AliRoot=$AliRootVer)"
fi

CleanUp
return 0
