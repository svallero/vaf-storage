#!/bin/bash

#
# af-proof-nodes.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Adds or removes one or more PROOF nodes to or from the dynamic PROOF
# configuration file, i.e. proof.conf.
#
# It works by taking parameters from the command line, or remotely by guessing
# the caller host via SSH standard variables.
#

# Load AF configuration
source /etc/aafrc || exit 1

# Maximum number of seconds to wait for a lock
export LockLimit=15

# The proof.conf
export ProofConf="$AF_PREFIX/etc/proof/proof.conf"

# Known hosts for SSH
export KnownHosts="$HOME/.ssh/known_hosts"

# TCP Ports to check (usually, ssh, xrootd, proof)
export CheckPorts=( 22 1093 1094 )

# Print messages on /var/log/messages if 1
export Logger=0

# Prints a message
function Msg() {
  if [ "$Logger" == 1 ] ; then
    logger -t af-proof-nodes "$1"
  else
    echo -e "\033[1m$1\033[m" >&2
  fi
}

# Lock/Wait function to regulate access to a certain file
function LockWait() {

  local LockDir="$1.lock"
  local LockSuccess=1
  local LockCount=0

  while ! mkdir "$LockDir" 2> /dev/null ; do
    if [ $LockCount == $LockLimit ] ; then
      LockSuccess=0
      break
    fi
    sleep 1
    let LockCount++
  done

  # At this point we've given up waiting
  if [ $LockSuccess == 0 ] ; then
    Msg "Given up waiting to acquire lock over $1" >&2
    return 1
  fi

  # Remove lock in case of exit/abort/etc. (only sigkill is uninterruptible)
  trap "Unlock $1" 0

  return 0
}

# Removes lock for a certain file
function Unlock() {
  rmdir "$1.lock" 2> /dev/null
  trap '' 0  # unset EXIT traps
}

# List hosts and workers
function ListWorkers() {
  Msg 'List of host / num. of workers:'
  grep ^worker "$ProofConf" | sort | uniq -c | \
    perl -ne '/([0-9]+)\s+worker\s+([^\s]+)/ and print "  $2 / $1\n"' | \
    while read Line ; do Msg "  $Line" ; done
}

# Add hosts and workers. Each argument has the format host.domain/nwrk
function AddHosts() {

  local HostNcores Host Ncores Nwrk

  LockWait "$ProofConf" || return 1

  while [ "$#" -ge 1 ] ; do
    HostNcores="$1"

    Host=${HostNcores%/*}
    Ncores=${HostNcores##*/}

    # Was Ncores given, and is it a number?
    [ "$Ncores" == "$HostNcores" ] && Ncores=1
    let Ncores+=0 2> /dev/null
    [ $? != 0 ] || [ $Ncores == 0 ] && Ncores=1

    # Always removes host
    grep -v "worker $Host" "$ProofConf" > "$ProofConf.0" && \
      rm -f "$ProofConf" && \
      mv "$ProofConf.0" "$ProofConf" || return 1

    # Compute number of workers to assing starting from a config variable and
    # the given number of cores
    Nwrk=`echo "a=$Ncores*$AF_PROOF_WORKERS_PER_CORE+0.5;scale=0;a/=1;a" | bc`

    # Add Nwrk times
    for i in `seq 1 $Nwrk` ; do
      echo "worker $Host" >> "$ProofConf"
    done

    # Syncing configuration and packages for host
    "$AF_PREFIX"/bin/af-sync -a "$Host"

    Msg "Host $Host added with $Nwrk worker(s)"

   shift 1
  done

  Unlock "$ProofConf"

}

# Add host key to known hosts. First argument is the key, others are host
# aliases. Existing keys are removed from known_host beforehand. Duplicate
# aliases are pruned
function AddHostKey() {

  local HostKey="$1"
  local Host="$2"
  local Aliases
  shift 1

  # List of aliases separated by a pipe, ready for grepping
  Aliases=$(
    while [ $# -ge 1 ] ; do
      echo \|$1
      shift
    done | sort -u | xargs -L1 echo -n
  )
  Aliases=${Aliases:1}

  # Remove old keys
  LockWait "$KnownHosts" || return 1
  cat "$KnownHosts" | egrep -v "$Aliases" > "$KnownHosts".0
  mv "$KnownHosts".0 "$KnownHosts"

  # Add new key
  Aliases=`echo $Aliases | sed -e 's#|#,#g'`
  echo "$Aliases $HostKey" >> "$KnownHosts"
  #ssh-keyscan -t rsa "$Host" | \
  #  sed -e 's#'$Host'#'"$Aliases"'#' >> "$KnownHosts"
  Unlock "$KnownHosts"

  return 0
}

# Remove hosts: takes hosts as arguments
function RemoveHosts() {

  local GrepStr

  LockWait "$ProofConf" || return 1

  while [ "$#" -ge 1 ] ; do
    [ "$GrepStr" == '' ] && \
      GrepStr="worker $1\$" || \
      GrepStr="$GrepStr|worker $1\$"
    shift 1
  done

  cat "$ProofConf" | \
    egrep -v "$GrepStr" > "$ProofConf".0 && \
    rm -f "$ProofConf" && \
    mv "$ProofConf".0 "$ProofConf"

  Unlock "$ProofConf"

}

# List hosts and workers
function CleanupWorkers() {
  local P Host Ok ToRemove Tmp

  Tmp=`mktemp /tmp/af-proof-nodes-XXXXX`

  #Msg 'Cleaning up inactive workers...'

  grep ^worker "$ProofConf" | sort | uniq -c | \
    perl -ne '/[0-9]+\s+worker\s+([^\s]+)/ and print "$1\n"' > $Tmp

  while read Host ; do
    Ok=0
    for P in ${CheckPorts[@]} ; do
      nc -z $Host $P &> /dev/null
      if [ $? == 0 ] ; then
        Ok=1
        break
      fi
    done

    if [ $Ok == 0 ] ; then
      #Msg "  $Host: unreachable!"
      ToRemove="$ToRemove $Host"
    #else
    #  Msg "  $Host: active"
    fi

  done < $Tmp
  rm -f $Tmp

  if [ "$ToRemove" != '' ] ; then
    Msg "Workers found inactive: `echo $ToRemove`"
    eval "RemoveHosts $ToRemove" || return $?
  else
    Msg "No dead PROOF workers found"
  fi

}

# Accepts commands from a remote host
function RemoteMode() {

  local Ip Host Nwrk Command

  # Get hostname from SSH environment
  if [ "$SSH_CLIENT" == '' ] ; then
    Msg 'No SSH_CLIENT in environment!'
    return 1
  fi

  # Get caller's IP address from the SSH variable
  Ip=$(echo $SSH_CLIENT | awk '{ print $1 }')

  # Get hostname from the IP address
  Host=$(getent hosts $Ip 2> /dev/null | awk '{ print $2 }')

  # Check if we really have the host name
  if [ "$Host" == '' ] ; then
    Msg 'Hostname cannot be retrieved!'
    return 1
  fi

  # Get the command
  read Command
  case $Command in
    add*)
      Nwrk=`echo $Command | cut -d' ' -f2`
      HostKey=`echo $Command | cut -d' ' -f3-`
      AddHostKey "$HostKey" $Host ${Host%%.*} $Ip || return $?
      AddHosts "$Host/$Nwrk" || return $?
    ;;
    delete)
      RemoveHosts "$Host" || return $?
    ;;
  esac

}

function PrintHelp() {
  local Tmp OldIFS
  Tmp=`mktemp /tmp/af-proof-nodes-XXXXX`
  cat > $Tmp <<_EOF_
`basename $0` -- by Dario Berzano <dario.berzano@cern.ch>
Manages dynamic addition and removal of PROOF workers, both manually and
automatically.

Usage: `basename $0` [options] Node1 Node2...
      --remote,-r                  SSH command mode: accepts commands on stdin
      --add,-a                     adds nodes (in format: <node.dom>/<cores>)
      --delete,-d                  deletes nodes
      --list                       list current nodes with n. workers
      --cleanup                    checks and cleans up inactive workers
      --logger                     output on system's log facility
      --help                       this help screen
_EOF_
  OldIFS="$IFS"
  IFS="\n"
  while read Line ; do
    echo "$Line"
  done < "$Tmp"
  IFS="$OldIFS"
  rm -f "$Tmp"
}

# The main function
function Main() {

  local Prog Args Remote AddHostWorkers DeleteHost List

  Prog=$(basename "$0")

  Args=$(getopt -o 'radlc' \
    --long 'remote,add,delete,list,cleanup, logger' -n"$Prog" -- "$@")
  [ $? != 0 ] && exit 1

  eval set -- "$Args"

  while [ "$1" != "--" ] ; do

    case "$1" in

      --remote|-r)
        Mode='remote'
        shift 1
      ;;

      --add|-a)
        Mode='add'
        shift 1
      ;;

      --delete|-d)
        Mode='delete'
        shift 1
      ;;

      --list|-l)
        Mode='list'
        shift 1
      ;;

      --cleanup|-c)
        Mode='cleanup'
        shift 1
      ;;

      --logger)
        Logger=1
        shift 1
      ;;

      *)
        # Should never happen
        Msg "Ignoring unknown option: $1"
        shift 1
      ;;

    esac

  done

  shift # --

  case "$Mode" in

    remote)
      RemoteMode
    ;;

    add)
      AddHosts "$@"
    ;;

    delete)
      RemoveHosts "$@"
    ;;

    list)
      ListWorkers
    ;;

    cleanup)
      CleanupWorkers
    ;;

    help|*)
      PrintHelp
      exit 1
    ;;

  esac || Msg 'A fatal error occured, aborting.' >&2

}

#
# Entry point
#

Main "$@"
