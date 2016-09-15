#!/bin/bash

#
# push-puppet.sh -- by Dario Berzano <dario.berzano@cern.ch>
#
# Pushes current PROOF configuration to Puppet, which will deploy it to other
# hosts.
#

# Source environment variables
source /etc/aafrc 2> /dev/null
if [ $? != 0 ]; then
  echo 'Can not find configuration file /etc/aafrc.' >&2
  exit 1
fi

# Files to copy (wrt/ AF_PREFIX)
Files=(
  '/etc/proof/XrdSecgsiGMAPFunLDAP.cf'
  '/etc/af-monalisa.cron'
  '/etc/aliroot_deps.conf'
  '/etc/env-alice.sh'
  '/etc/monalisa-conf.pl'
  '/etc/proof/grid-mapfile'
  '/etc/proof/groups.alice.cf'
  '/etc/proof/prf-main.cf'
  '/etc/xrootd/xrootd.cf'
  '/etc/xrootd/xrootd-startup.cf'
  '/etc/init.d/proof'
  '/etc/init.d/xrootd'
  '/bin/af-monalisa.pl'
  '/lib/perl-apmon/ApMon/ConfigLoader.pm'
  '/lib/perl-apmon/ApMon/ProcInfo.pm'
  '/lib/perl-apmon/ApMon/XDRUtils.pm'
  '/lib/perl-apmon/ApMon/BgMonitor.pm'
  '/lib/perl-apmon/ApMon/Common.pm'
  '/lib/perl-apmon/ApMon.pm'
  "/var/proof/proofbox/$AF_USER/packages"
)

# Main function
function Main() {

  local TmpDir

  # Temporary directory for configuration
  TmpDir=`mktemp -d /tmp/push-puppet-XXXX`

  # Stage needed files into temporary directory
  echo 'Staging needed files into a temporary directory:' >&2
  for F in "${Files[@]}" ; do
    mkdir -p `dirname "$TmpDir/$F"`
    cp -pr "$AF_PREFIX/$F" "$TmpDir/$F"
  done

  # Add global configuration file there
  cp -p /etc/aafrc "$TmpDir/etc/"

  # TODO: see permissions and --delete!

  # Send files to remote Puppet host via rsync
  echo 'Sending files via rsync:' >&2
  rsync -vrlt --delete "$TmpDir/" "$AF_DEPLOY_DEST"

  # Send files to xrootd server via rsync (TODO)
  echo 'Sending files to xrootd server via rsync:' >&2
  rsync -av "$TmpDir/" root@alice-srv-11.to.infn.it:/opt/aaf

  # Clean up
  rm -rf "$TmpDir"

}

#
# Entry point
#

Main "$@"
