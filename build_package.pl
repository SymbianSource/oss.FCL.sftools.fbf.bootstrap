# Copyright (c) 2009 Symbian Foundation Ltd
# This component and the accompanying materials are made available
# under the terms of the License "Eclipse Public License v1.0"
# which accompanies this distribution, and is available
# at the URL "http://www.eclipse.org/legal/epl-v10.html".
#
# Initial Contributors:
# Symbian Foundation Ltd - initial contribution.
#
# Contributors:
#
# Description:
# This is a helper script which allocates unique drive letter and build number
# then starts a package build by running FBF bootstrap and build targets

use strict;

use Getopt::Long;
use File::Path;

my $sBOOTSTRAP_DIR="C:\\Apps\\FBF\\bootstrap";
my $sJOB_BASE_DIR="D:\\fbf_project";
my $nMAX_JOBDIR_AGE_SECONDS = 86400; # max number of seconds after which the letter is forcibly released
my $nLOCK_FILE_MAX_ATTEMPTS = 5;
my $sNUMBERS_FILE="\\\\v800008.ad-sfpd.intra\\g\$\\numbers.txt";
my $sLETTERS_FILE="D:\\letters.txt";
my $nMAX_LETTER_AGE_SECONDS = 86400; # max number of seconds after which the letter is forcibly released

my $sFbfProjectRepo = '';
my $sFbfProjectDir = '';
my $sFbfConfigRepo="\\\\v800008.ad-sfpd.intra\\g\$\\mercurial_internal\\fbf\\configs\\pkgbuild";
my $sFbfConfigDir = '';
my $sJobLabel = '';
my $nCmdLineNumber;
my $bTestBuild = 0;
GetOptions((
	'label:s' => \$sJobLabel,
	'configrepo:s' => \$sFbfConfigRepo,
	'configdir:s' => \$sFbfConfigDir,
	'projectrepo:s' => \$sFbfProjectRepo,
	'projectdir:s' => \$sFbfProjectDir,
	'number:s' => \$nCmdLineNumber,
	'testbuild!' => \$bTestBuild
));

if (!$sJobLabel or !($sFbfProjectRepo or $sFbfProjectDir))
{
	print "Usage: build_package.pl --label=LABEL (--projectrepo=REPO | --projectdir=DIR) OPTIONS\n";
	print "\tOPTIONS:\n";
	print "\t--configrepo=REPO Use REPO location for the config instead of \\\\v800008\\g\$\\mercurial_development\\oss\\FCL\\interim\\fbf\\config\\pkgbuild\\n";
	print "\t--configdir=DIR Use DIR location for the config (exclusive with --configrepo)\n";
	print "\t--number=N Force build number to N\n";
	print "\t--testbuild Use d:\\numbers_test.txt for numbers and d:\\SF_builds_test to publish results\n";
	exit(0);
}

my $sTestBuildOpts = "";
$sTestBuildOpts = "-Dsf.spec.publish.networkdrive=d:\\SF_builds_test" if ( $bTestBuild );
$sNUMBERS_FILE = "d:\\numbers_test.txt" if ( $bTestBuild );

my $sJobDir = mkdir_unique("$sJOB_BASE_DIR\\$sJobLabel");

print("cd $sBOOTSTRAP_DIR\n");
chdir("$sBOOTSTRAP_DIR");
print "###### BOOTSTRAP ######\n";
my $sConfigArg = "-Dsf.config.repo=$sFbfConfigRepo";
$sConfigArg = "-Dsf.config.dir=$sFbfConfigDir" if ($sFbfConfigDir);
my $sProjectArg = "-Dsf.project.repo=$sFbfProjectRepo";
$sProjectArg = "-Dsf.project.dir=$sFbfProjectDir" if ($sFbfProjectDir);
print("hlm -f bootstrap.xml $sConfigArg $sProjectArg -Dsf.target.dir=$sJobDir\n");
system("hlm -f bootstrap.xml $sConfigArg $sProjectArg -Dsf.target.dir=$sJobDir");

# check that $sNUMBERS_FILE exists, otherwise create it
if (!-f $sNUMBERS_FILE)
{
	open FILE, ">$sNUMBERS_FILE";
	print FILE "\n";
	close FILE;
}

my $nUnformattedNumber = ( $nCmdLineNumber ? $nCmdLineNumber : get_job_number($sFbfProjectRepo));
my $nJobNumber = sprintf("%.3d", $nUnformattedNumber);

# check that $sLETTERS_FILE exists, otherwise create it
if (!-f $sLETTERS_FILE)
{
	open FILE, ">$sLETTERS_FILE";
	print FILE "\n";
	close FILE;
}

# acquire drive letter
my $sDriveLetter = acquire_drive_letter();
print "acquired drive letter: $sDriveLetter\n";
die "Could not acquire drive letter" if (! $sDriveLetter);

print("cd $sJobDir\\sf-config\n");
chdir("$sJobDir\\sf-config");
print "###### BUILD PREPARATION ######\n";
print("hlm sf-prep -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpts\n");
system("hlm sf-prep -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpts");

print "###### EXECUTE BUILD ######\n";
print("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter:\n");
system("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter:");

# release the drive letter
release_drive_letter($sDriveLetter);
system("subst $sDriveLetter: /d"); # this is not required, but it's a good idea to keep things in order
print "drive letter $sDriveLetter released (and drive unsubsted)\n";

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
	
	$sKey=lc($sKey);
	
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
				$hnNumbers{lc($1)} = $2 if ($sLine =~ m%(.*),(.*)%);
			}
			
			$hnNumbers{$sKey} = 0 if (! $hnNumbers{$sKey} );
			$hnNumbers{$sKey} = $hnNumbers{$sKey} + 1;
			
			seek(FILE, 0, 0);

			for my $sStr ( keys(%hnNumbers) )
			{
				print FILE "$sStr,$hnNumbers{$sStr}\n";
			}
			truncate(FILE,tell(FILE));
			
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

sub acquire_drive_letter
{
	my %hsPidsAndTimestamps = ();
	
	my $sLetterToRelease = '';
	
	my $nAttempts = 0;
	my $bAcquired = 0;
	do
	{
		open(FILE, "+<$sLETTERS_FILE") or die("Can't open $sLETTERS_FILE");
		if ( flock(FILE, 6) )
		{
			my $sLine;
			while ($sLine = <FILE>)
			{
				if ($sLine =~ m%([^,]*),(.*)%)
				{
					my $sLetter=$1;
					my $sString=$2;
					
					$sString=~m%([^,]*),(.*)%;
					my $nPid=$1;
					my $nTimestamp=$2;
					
					if (time()-$nTimestamp<=$nMAX_LETTER_AGE_SECONDS)
					{
						$hsPidsAndTimestamps{$sLetter} = $sString;
					}
					else
					{
						# lease has expired: unsubst drive letter and don't add to hash
						system("subst $sLetter: /d");
						print "forced release of letter: $sLetter (and drive unsubsted)\n";
					}
				}
			}
			
			for my $sNewLetter ('H'..'Y')
			{
				if (! $hsPidsAndTimestamps{$sNewLetter})
				{
					my $sTimestamp = time();
					$hsPidsAndTimestamps{$sNewLetter} = "$$,$sTimestamp";
					$sLetterToRelease = $sNewLetter;
					last;
				}
			}
			
			seek(FILE, 0, 0);

			for my $sLetter ( keys(%hsPidsAndTimestamps) )
			{
				print FILE "$sLetter,$hsPidsAndTimestamps{$sLetter}\n";
			}
			truncate(FILE,tell(FILE));
			
			$bAcquired = 1;
		}
		else
		{
			$nAttempts ++;
			sleep(3);
		}
		close(FILE);
	}
	until ( $bAcquired or $nAttempts == $nLOCK_FILE_MAX_ATTEMPTS );
	
	return $sLetterToRelease;
}

sub release_drive_letter
{
	my ($sLetterToRelease) = @_;
	
	my %hsPidsAndTimestamps = ();
	
	my $nAttempts = 0;
	my $bAcquired = 0;
	do
	{
		open(FILE, "+<$sLETTERS_FILE") or die("Can't open $sLETTERS_FILE");
		if ( flock(FILE, 6) )
		{
			my $sLine;
			while ($sLine = <FILE>)
			{
				$hsPidsAndTimestamps{$1} = $2 if ($sLine =~ m%([^,]*),(.*)%);
			}
			
			delete $hsPidsAndTimestamps{$sLetterToRelease};
			
			seek(FILE, 0, 0);

			for my $sLetter ( keys(%hsPidsAndTimestamps) )
			{
				print FILE "$sLetter,$hsPidsAndTimestamps{$sLetter}\n";
			}
			truncate(FILE,tell(FILE));
			
			$bAcquired = 1;
		}
		else
		{
			$nAttempts ++;
			sleep(3);
		}
		close(FILE);
	}
	until ( $bAcquired or $nAttempts == $nLOCK_FILE_MAX_ATTEMPTS );
}
