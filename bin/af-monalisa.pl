#!/usr/bin/perl

#
# af-monalisa.pl -- by Dario Berzano <dario.berzano@cern.ch>
#
# Sends analysis facility dynamic information to a configured MonALISA service.
#

# Standard use directives
use strict;
use warnings;

# Includes configuration (wrt/ script directory)
BEGIN {
  use File::Basename;
  my $configFile = dirname($0) . "/../etc/monalisa-conf.pl";
  require $configFile;
}

# Packages
use Net::Domain;
use ApMon;

# Re-define variables in the external configuration file
our $masterHost;
our $proofConnectAlias;
our $apMonClusterPrefix;
our $apMonHostPort;
our $apStatus;
our $apRootVer;
our $storagePath;

my $apm = new ApMon( {"${apMonHostPort}" => {}} );
my $thisHost = Net::Domain::hostfqdn();

my $apMonCluster       = "${apMonClusterPrefix}_xrootd_Nodes";
my $apMonClusterMaster = "${apMonClusterPrefix}_manager_xrootd_Services";

my $apNWorkers     = -1;
my $apNSessions    = -1;
my $apProofUp      = -1;
my $apSpaceTotalMb = -1;
my $apSpaceFreeMb  = -1;

if ($masterHost eq $thisHost) {

  #
  # On master
  #

  # Number of workers (there must be a better way...)
  open(FP, "cat /opt/aaf/etc/proof/proof.conf | grep -v '#' | " .
    "grep 'worker ' | wc -l |");
  $apNWorkers = <FP> + 0;  # force cast
  close(FP);

  # Connected users: count proofserv.exe on master
  open(FP, "ps ax -o user,command | grep proofserv.exe | grep -v grep | " .
    "cut -f1 -d' ' | sort | uniq | wc -l |");
  $apNSessions = <FP> + 0;
  close(FP);

  # Free disk space
  ($apSpaceTotalMb, $apSpaceFreeMb) =
    `df -P -B 1048576 "$storagePath" | tail -n1` =~
    m/\s+([0-9]+)\s+[0-9]+\s+([0-9]+)/;
  $apSpaceTotalMb += 0;
  $apSpaceFreeMb += 0;

}
else {

  #
  # On a worker
  #

  # Count activated slaves
  open(FP, "ps aux | grep 'proofslave' | grep -v grep | wc -l |");
  $apNSessions = <FP> + 0;
  close(FP);

}

# Is PROOF up?
open(FP, "ps aux | grep bin/xproofd | grep -v grep | wc -l|");
$apProofUp = (<FP> != 0);

# Report all the gathered information
print "Number of workers:  [$apNWorkers]\n";
print "Number of sessions: [$apNSessions]\n";
print "Status:             [$apStatus]\n";
print "PROOF up:           [$apProofUp]\n";
print "ROOT version:       [$apRootVer]\n";
print "Total space [Mb]:   [$apSpaceTotalMb]\n";
print "Free space [Mb]:    [$apSpaceFreeMb]\n";

# Send host info
$apm->sendParameters($apMonCluster, $thisHost, {
  "proofserv_count"       => $apNSessions,
  "xproofd_up"            => $apProofUp,
  "aaf_root_ver"          => $apRootVer
});

# On master only, send extra info
$apm->sendParameters($apMonClusterMaster, $thisHost, {
  "proofserv_count"   => $apNSessions,
  "xproofd_up"        => $apProofUp,
  "aaf_root_ver"      => $apRootVer,
  "aaf_proof_alias"   => $proofConnectAlias,
  "aaf_proof_workers" => $apNWorkers,
  "aaf_status"        => $apStatus,
  "space_free"        => $apSpaceFreeMb,
  "space_total"       => $apSpaceTotalMb
}) if ($masterHost eq $thisHost);
