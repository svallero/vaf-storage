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
export GridPackagesRegexp='^.*-AN$'

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
  pecho '      --list                       lists all [G]rid and/or [L]ocal packages'
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
    rm -rf "$PackageDir"
  done

}

# Adds a specific Grid package locally, or all "new" packages, i.e. all packages
# available on the Grid but not installed locally
function AddGridPackage() {

  local ListOk=''
  local ListFail=''

  if [ "$1" != 'new' ] ; then
    # Adding a single package
    InstallPackage "$1" || return 1
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
    InstallPackage "$N"
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

Args=$(getopt -o '' --long 'clean:,add:,list,sync,help' -n"$Prog" -- "$@")
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

    --sync)
      CleanPackage='old'
      AddPackage='new'
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
  [ "$AddPackage" == '' ] ; then
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

"$AF_PREFIX"/bin/af-create-deps.rb "$@"
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
fi

# Add packages
if [ "$AddPackage" != '' ] ; then
  AddGridPackage "$AddPackage"
fi
