#!/usr/bin/perl -w

use strict;

use Getopt::Long;
use File::Path;

my $sBOOTSTRAP_DIR="D:\\Helium\\hlm-apps\\bootstrap";
my $sJOB_BASE_DIR="D:\\fbf_project";
my $sCONFIG_REPO="\\\\lon-engbuild87\\d\$\\mercurial_development\\epl\\interim\\fbf\\configs\\pkgbuild\\FCL_pkgbuild";
my $nLOCK_FILE_MAX_ATTEMPTS = 5;
my $sNUMBERS_FILE="\\\\sym-build01\\f\$\\numbers.txt";

my $sProjectRepo = '';
my $sJobLabel = '';
my $nCmdLineNumber;
GetOptions(('label:s' => \$sJobLabel, 'project:s' => \$sProjectRepo, 'number:s' => \$nCmdLineNumber));

if (!$sJobLabel or !$sProjectRepo)
{
	print "Usage: build_package.pl --label=<label> --project=<project_repo>\n";
	exit(0);
}

my $sJobDir = mkdir_unique("$sJOB_BASE_DIR\\$sJobLabel");

print("cd $sBOOTSTRAP_DIR\n");
chdir("$sBOOTSTRAP_DIR");
print "###### BOOTSTRAP ######\n";
print("hlm -f bootstrap.xml -Dsf.config.repo=$sCONFIG_REPO -Dsf.project.repo=$sProjectRepo -Dsf.target.dir=$sJobDir\n");
system("hlm -f bootstrap.xml -Dsf.config.repo=$sCONFIG_REPO -Dsf.project.repo=$sProjectRepo -Dsf.target.dir=$sJobDir");


my $nUnformattedNumber = ( $nCmdLineNumber ? $nCmdLineNumber : get_job_number($sProjectRepo));
my $nJobNumber = sprintf("%.3d", $nUnformattedNumber);

print("cd $sJobDir\\sf-config\n");
chdir("$sJobDir\\sf-config");
print "###### BUILD PREPARATION ######\n";
print("hlm sf-prep -Dsf.spec.job.number=$nJobNumber\n");
system("hlm sf-prep -Dsf.spec.job.number=$nJobNumber");

print "###### EXECUTE BUILD ######\n";
print("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber\n");
system("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber");

sub mkdir_unique
{
	my ($sBaseDir) = @_;
	
	# check that the path where the new dir must be created exists.
	$sBaseDir =~ m,(.*[\\/])?(.*),;
	mkpath($1) if ($1 && !-d $1);
	
	my $nI = 0;
	my $sNewDirName = "$sBaseDir";
	while(!mkdir($sNewDirName))
	{
		$nI++;
		$sNewDirName = "$sBaseDir.$nI";
	}
	
	return $sNewDirName;
}

sub get_job_number
{
	my ($sKey) = @_;
	
	my %hnNumbers = ();
	
	my $nAttempts = 0;
	my $bGotNumber = 0;
	do
	{
		open(FILE, "+<$sNUMBERS_FILE") or die("Can't open $sNUMBERS_FILE");
		if ( flock(FILE, 6) )
		{
			my $sLine;
			while ($sLine = <FILE>)
			{
				$hnNumbers{$1} = $2 if ($sLine =~ m%(.*),(.*)%);
			}
			
			$hnNumbers{$sKey} = 0 if (! $hnNumbers{$sKey} );
			$hnNumbers{$sKey} = $hnNumbers{$sKey} + 1;
			
			seek(FILE, 0, 0);

			for my $sStr ( keys(%hnNumbers) )
			{
				print FILE "$sStr,$hnNumbers{$sStr}\n";
			}
			
			$bGotNumber = 1;
		}
		else
		{
			$nAttempts ++;
			sleep(3);
		}
		close(FILE);
	}
	until ( $bGotNumber or $nAttempts == $nLOCK_FILE_MAX_ATTEMPTS );
	
	return $hnNumbers{$sKey};
}
