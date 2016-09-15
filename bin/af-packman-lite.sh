#!/bin/bash

#
# af-packman-lite.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Lightweight replacement for Alien Packman which uses the ALICE Grid packages
# webpage to retrieve installation scripts for the various AliRoot versions.
#

source /etc/aafrc || exit 1

#
# Global variables
#

export GridPackages=''
export LocalPackages=''
export GridPackagesRegexp='^.*-AN(-[0-9]+)?$'
export Dry='echo'

# Program name
Prog=`basename "$0"`

# Colored echo on stderr
function pecho() {
  local NewLine=''
  if [ "$1" == -n ]; then
    NewLine='-n'
    shift
  fi
  echo -e $NewLine "\033[1m$1\033[m" >&2
}

# Prints help
function PrintHelp {

  local Prog
  Prog=`basename "$0"`

  pecho "$Prog -- by Dario Berzano <dario.berzano@cern.ch>"
  pecho "Lightweight replacement for Alien Packman which uses the ALICE Grid"
  pecho "packages webpage to retrieve installation scripts for the various"
  pecho "AliRoot versions."
  pecho ''
  pecho "Usage: $Prog [options]"
  pecho '      --clean PACKAGE              removes PACKAGE (or "old")'
  pecho '      --add PACKAGE                adds PACKAGE (or "new")'
  pecho '      --sync                       removes old and adds new packages'
  pecho '      --cleanup-deps               removes unneeded Geant3/ROOT'
  pecho '      --list                       lists packages ([G]rid/[L]ocal)'
  pecho '      --proof                      repeats action on PROOF PARs too'
  pecho '      --no-dry-run                 turns off dry run (on by default)'
  pecho '      --help                       this help screen'

}

# Exports an array with the list of AliRoot packages from the webpage. Returns
# nonzero on error
function SetGridPackages() {

  GridPackages=''
  local Count=0

  while read Pack ; do
    GridPackages[$Count]="$Pack"
    let Count++
  done < <( curl -s http://alimonitor.cern.ch/packages/ | \
    perl -ne '/(VO_ALICE\@AliRoot::[A-Za-z0-9_-]+)/ and print "$1\n"' |
    perl -ne '/'"$GridPackagesRegexp"'/ and print "$_"' )

  # Check number of packages -- if zero, it's likely we have a problem
  if [ ${#GridPackages[@]} == 0 ] ; then
    return 1
  fi

  return 0
}

# Exports an array with the list of local AliRoot packages
function SetLocalPackages() {

  LocalPackages=''
  local Count=0

  while read Pack ; do
    LocalPackages[$Count]="VO_ALICE@AliRoot::$Pack"
    let Count++
  done < <( find "$AF_PACK_DIR"/VO_ALICE/AliRoot -maxdepth 1 -mindepth 1 \
    -type d | xargs -L1 basename )

}

# Prints out the list of packages currently available locally and on the Grid
function ListAllPackages() {

  # Creates one big list
  local MergedPackages="${GridPackages[@]} ${LocalPackages[@]}"

  # Sort, uniq
  MergedPackages=$( for Pack in $MergedPackages ; do
    echo "$Pack"
  done | sort -u )

  local InGrid
  local InLocal

  pecho 'List of AliRoot packages on the Grid [G] and installed locally [L]:'

  # Print line by line
  for Pack in $MergedPackages ; do

    InGrid=' '
    InLocal=' '

    # Is in Grid?
    for P in "${GridPackages[@]}" ; do
      if [ "$Pack" == "$P" ] ; then
        InGrid='G'
        break
      fi
    done

    # Is it local?
    for P in "${LocalPackages[@]}" ; do
      if [ "$Pack" == "$P" ] ; then
        InLocal='L'
        break
      fi
    done

    echo "[${InGrid}${InLocal}] $Pack"

  done

}

# Clean a specific package, or all "old" ones. The meaning of "old" is: all
# packages installed locally but not present on the Grid
function CleanGridPackage() {

  local PackageDir FullPackage

  if [ "$1" != 'old' ] ; then

    # Cleans a specific package. Beware: dependencies are not removed [TODO]
    FullPackage="$1"
    PackageDir="${FullPackage##*:}"
    PackageDir="$AF_PACK_DIR/VO_ALICE/AliRoot/$PackageDir"

    pecho "Cleaning package $1 from local repository:"
    if [ ! -d "$PackageDir" ] ; then
      echo "Package $FullPackage not found!"
    else
      rm -rf "$PackageDir" || \
        echo "Package $FullPackage cannot be removed!" && \
        echo "Package $FullPackage removed"
    fi || return 1

  fi

  # Here we clean up "old" packages only
  local OldPackages=''
  local IsOld

  for L in "${LocalPackages[@]}" ; do
    IsOld=1
    for G in "${GridPackages[@]}" ; do
      if [ "$L" == "$G" ] ; then
        IsOld=0
      fi
    done

    [ $IsOld == 1 ] && OldPackages="$OldPackages $L"

  done

  # List old ones?
  pecho 'List of old packages candidate for removal:'
  if [ "$OldPackages" == '' ] ; then
    pecho 'No old packages'
    return 0
  fi

  for O in $OldPackages ; do
    echo $O
  done
  pecho 'Do you want to remove them?'
  echo -n 'Answer capital YES if so: '
  read Ans

  if [ "$Ans" != 'YES' ] ; then
    pecho 'Aborted.'
    return 1
  fi

  # Proceed with deletion
  for O in $OldPackages ; do

    FullPackage="$O"
    PackageDir="${FullPackage##*:}"
    PackageDir="$AF_PACK_DIR/VO_ALICE/AliRoot/$PackageDir"

    pecho "Removing $FullPackage"
    $Dry rm -rf "$PackageDir"
  done

}

# Removes unneeded dependencies from local repository
function CleanupDeps() {
  local Geant3Versions=''
  local RootVersions=''
  local G3Ver RootVer Ali G3VerShort RootVerShort

  pecho 'Finding unneeded ROOT and Geant3 versions...'

  for Ali in ${LocalPackages[@]} ; do
    Deps=`grep "$Ali" "$AF_DEP_FILE" | head -n1`
    [ "$Deps" == '' ] && continue

    RootVer=`echo $Deps | cut -d\| -f2 | sed -e 's#VO_ALICE@ROOT::##'`
    G3Ver=`echo $Deps | cut -d\| -f3 | sed -e 's#VO_ALICE@GEANT3::##'`

    echo "$RootVersions" | grep -q "$RootVer" || \
      RootVersions="$RootVersions $RootVer"

    echo "$Geant3Versions" | grep -q "$G3Ver" || \
      Geant3Versions="$Geant3Versions $G3Ver"
  done

  # Now we have the legitimate ROOT and Geant3 versions in two variables. List
  # extra ones
  Geant3Versions=`echo $Geant3Versions`
  Geant3Versions=`echo $Geant3Versions\$|sed -e 's# #$|#g'`
  RootVersions=`echo $RootVersions`
  RootVersions=`echo $RootVersions\$|sed -e 's# #$|#g'`

  # Geant3
  for G3Ver in "$AF_PACK_DIR/VO_ALICE/GEANT3/"* ; do
    echo $G3Ver | egrep -q "$Geant3Versions"
    if [ $? != 0 ]; then
      G3VerShort=`basename "$G3Ver"`
      pecho "Removing Geant3 $G3VerShort..."
      $Dry rm -rf "$G3Ver"
    fi
  done

  # ROOT
  for RootVer in "$AF_PACK_DIR/VO_ALICE/ROOT/"* ; do
    echo $RootVer | egrep -q "$RootVersions"
    if [ $? != 0 ]; then
      RootVerShort=`basename "$RootVer"`
      pecho "Removing ROOT $RootVerShort..."
      $Dry rm -rf "$RootVer"
    fi
  done

}

# Adds a specific Grid package locally, or all "new" packages, i.e. all packages
# available on the Grid but not installed locally
function AddGridPackage() {

  local ListOk=''
  local ListFail=''

  if [ "$1" != 'new' ] ; then
    # Adding a single package
    $Dry InstallPackage "$1" || return 1
  fi

  # Adding all "new" packages
  local NewPackages=''
  for G in "${GridPackages[@]}" ; do
    PackageDir="$AF_PACK_DIR/VO_ALICE/AliRoot/${G##*:}"
    [ ! -d "$PackageDir" ] && NewPackages="$NewPackages $G"
  done

  # Install new packages
  for N in $NewPackages ; do
    pecho "Adding $N"
    $Dry InstallPackage "$N"
    if [ $? != 0 ] ; then
      [ "$AbortOnError" == 1 ] && return 1 || ListFail="$ListFail $N"
    else
      ListOk="$ListOk $N"
    fi
  done

  # Report
  pecho "$( echo Packages OK: $ListOk )"
  pecho "$( echo Packages failed: $ListFail )"

}

# Install package wrapper. Use full package name, i.e.: VO_ALICE@AliRoot::<ver>
function InstallPackage() {
  local Pack="$1"
  local UrlEncPack=$( echo $Pack | sed -e 's#@#%40#g;s#:#%3A#g' )

  pecho "Installing package $Pack (might take time)..."

  ( cd "$AF_PACK_DIR/.." && curl -o install.sh \
    "http://alimonitor.cern.ch/packages/install.jsp?package=$UrlEncPack" && \
    chmod +x install.sh && ./install.sh )

  local RetVal=$?
  rm -f "$AF_PACK_DIR/../install.sh"

  if [ "$RetVal" == 0 ] ; then
    pecho "Installation of $Pack successful"
  else
    pecho "Installation of $Pack failed"
    return 1
  fi

  return 0

}

#
# Entry point
#

Prog=$(basename "$0")

Args=$(getopt -o '' \
  --long 'clean:,add:,list,sync,proof,cleanup-deps,no-dry-run,help' \
  -n"$Prog" -- "$@")
[ $? != 0 ] && exit 1

eval set -- "$Args"

while [ "$1" != "--" ] ; do

  case "$1" in

    --clean)
      CleanPackage="$2"
      shift 2
    ;;

    --add)
      AddPackage="$2"
      shift 2
    ;;

    --list)
      ListPackages=1
      shift 1
    ;;

    --cleanup-deps)
      CleanupDeps=1
      shift 1
    ;;

    --sync)
      CleanPackage='old'
      AddPackage='new'
      shift 1
    ;;

    --no-dry-run)
      Dry=''
      shift 1
    ;;

    --proof)
      Proof='1'
      shift 1
    ;;

    --abort)
      export AbortOnError=1
    ;;

    --help)
      PrintHelp
      exit 1
    ;;

    *)
      # Should never happen
      pecho "Ignoring unknown option: $1"
      shift 1
    ;;

  esac

done

shift # --

# Nothing to do? Help screen
if [ "$CleanPackage" == '' ] && [ "$ListPackages" == '' ] && \
  [ "$AddPackage" == '' ] && [ "$CleanupDeps" != 1 ] ; then
  PrintHelp
  exit 0
fi

# Initialize list of Grid packages from the Web and locally. Dependency file is
# also created anew
SetLocalPackages
SetGridPackages
if [ $? != 0 ] ; then
  pecho 'Error retrieving list of Grid packages from MonALISA web page! Abort.'
  exit 1
fi

"$AF_PREFIX"/bin/af-create-deps.rb
if [ $? != 0 ] ; then
  pecho 'Cannot create dependencies! Abort.'
  exit 1
fi

# List AliRoot Grid packages, and exits immediately. Option incompatible with
# everything else
if [ "$ListPackages" != '' ] ; then
  ListAllPackages
  exit $?
fi

# Clean packages first
if [ "$CleanPackage" != '' ] ; then
  CleanGridPackage "$CleanPackage"
  ProofOpts="$ProofOpts --clean $CleanPackage"
fi

# Add packages
if [ "$AddPackage" != '' ] ; then
  AddGridPackage "$AddPackage"
  ProofOpts="$ProofOpts --add $AddPackage"
fi

# Last action is to cleanup old dependencies
if [ "$CleanupDeps" == 1 ] ; then
  SetLocalPackages  # maybe they changed!
  CleanupDeps
fi

# Rebuild dependency list
"$AF_PREFIX"/bin/af-create-deps.rb

# Invoke command to synchronize PROOF packages
if [ "$Proof" == 1 ] ; then
  pecho 'Reflecting action on PROOF packages...'
  $Dry "$AF_PREFIX"/bin/af-proof-packages.sh $ProofOpts
  exit $?
fi
