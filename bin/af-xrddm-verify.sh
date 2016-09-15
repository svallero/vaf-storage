#!/bin/bash

#
# af-xrddm-verify.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# This script downloads a file using xrddm and verifies the integrity of the
# zip archive and the main .root file.
#
# Martin's xrddm works much better than alien_cp, checks for zip file integrity
# and creates token automatically, if invalid.
#
# afdsmgrd variables are ignored: /etc/aafrc variables are used instead.
#

# Source automatic AliEn stuff
source /etc/aafrc || exit 1

# Source environment for xrddm and ROOT (AliEn is included)
source "$AF_PREFIX/etc/env-alice.sh" --root current || exit 1

# Exit on error
function Abort() {
  echo "FAIL $Url Reason: $1"
  exit 1
}

# Remove file and empty parents
function DeepRm() {
  local CurDir
  rm -f "$1"
  CurDir=$(dirname "$1")
  while [ "$CurDir" != "/" ]; do
    rmdir "$CurDir" || break
    echo $CurDir
    CurDir=$(dirname "$CurDir")
  done
}

#
# Entry point
#

export Url="$1"
Tree="$2"

PosixPath=${Url%%#*}
Anchor=${Url##*#}
[ "$Anchor" == "$Url" ] && Anchor=''

# They both work. The first one also resolves '.' and '..'
#PosixPath=$(readlink -m "$PosixPath")
PosixPath=$(echo "/$PosixPath" | sed 's#//*#/#g')

# Always (re)download by default
Download=1

if [ -e "$PosixPath" ] ; then

  # File already there, but it might be a partially downloaded zip that xrddm
  # has not had the chance to check yet! So, check for zip integrity here
  Ext=${PosixPath##*.}
  [ "$Ext" == "$PosixPath" ] && Ext=''
  Ext=$(echo "$Ext" | tr '[:upper:]' '[:lower:]')

  if [ "$Ext" == 'zip' ]; then
    # Exit code for zip -T failure is 8
    zip -T "$PosixPath" && Download=0 || DeepRm "$PosixPath"
  else
    # File is not a zipfile: do not re-download it
    Download=0
  fi

fi

# Download file if told so
if [ "$Download" == 1 ]; then

  # Alien path
  AlienPath=${PosixPath:${#AF_SHARED_DATA}}
  AlienPath="alien://$AlienPath"

  # Uncomment for debug
  #echo "Url       => $Url"
  #echo "PosixPath => $PosixPath"
  #echo "Anchor    => $Anchor"
  #echo "Tree      => $Tree"
  #echo "AlienPath => $AlienPath"
  #echo "Command   => xrddm -a $AlienPath $PosixPath ..."

  # Create destination directory structure
  mkdir -p $(dirname "$PosixPath") || Abort 'mkdir'

  # Copy file using xrddm, token is done automatically
  "$AF_PREFIX"/bin/xrddm -a "$AlienPath" "$PosixPath"
  if [ $? != 0 ]; then
    DeepRm "$PosixPath"
    Abort 'xrddm-error' # we can't distinguish if token/xrdcp/zip error :(
  fi
  chmod 0644 "$PosixPath"

fi

# Choose proper verification macro (standard ROOT or custom afdsmgrd)
if [ "$AF_CUSTOM_AFDSMGRD" == '' ]; then
  VerifyMacro="$ROOTSYS/etc/proof/afdsmgrd-macros/Verify.C"
else
  VerifyMacro="$AF_CUSTOM_AFDSMGRD/libexec/afdsmgrd-macros/Verify.C"
fi

# Now, re-assemble the anchor and check the file with ROOT; ROOT history is off
TempOut=$(mktemp /tmp/af-xrddm-verify-root.XXXXX)
export ROOT_HIST=0
root.exe -b -q \
  "$VerifyMacro"'("file://'$PosixPath\#$Anchor'", "'$Tree'")' 2>&1 | tee -a $TempOut

# Decide whether to remove the file or not: if integrity check fails, file
# should be removed to save space
grep '^OK ' $TempOut > /dev/null || DeepRm "$PosixPath"

# Remove output file
rm -f $TempOut
