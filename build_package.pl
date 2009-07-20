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
my $sNUMBERS_FILE="\\\\bishare\\SF_builds\\numbers.txt";
my $sLETTERS_FILE="D:\\letters.txt";
my $nMAX_LETTER_AGE_SECONDS = 86400; # max number of seconds after which the letter is forcibly released

my $sFbfProjectRepo = '';
my $sFbfProjectDir = '';
my $sFbfConfigRepo="\\\\bishare\\mercurial_internal\\fbf\\configs\\pkgbuild";
my $sFbfConfigDir = '';
my $nCmdLineNumber;
my $bTestBuild = 0;
my $bPublish = 1;
GetOptions((
	'configrepo:s' => \$sFbfConfigRepo,
	'configdir:s' => \$sFbfConfigDir,
	'projectrepo:s' => \$sFbfProjectRepo,
	'projectdir:s' => \$sFbfProjectDir,
	'number:s' => \$nCmdLineNumber,
	'testbuild!' => \$bTestBuild,
	'publish!' => \$bPublish
));

if (!$sFbfProjectRepo and !$sFbfProjectDir)
{
	print "Usage: build_package.pl --projectrepo=REPO [OPTIONS]\n";
	print "where OPTIONS are:\n";
	print "\t--projectrepo=REPO[#REV] Use repository REPO at revision REV for the project.\n";
	print "\t--projectdir=DIR Use DIR location for the project (exclusive with --projectrepo). Option --nopublish is required.\n";
	print "\t--configrepo=REPO[#REV] Use repository REPO at revision REV for the config (instead of \\\\bishare\\mercurial_internal\\fbf\\config\\pkgbuild)\n";
	print "\t--configdir=DIR Use DIR location for the config (exclusive with --configrepo). Option --nopublish is required.\n";
	print "\t--number=N Force build number to N\n";
	print "\t--testbuild Set category to package.test and use Tnnn numbering\n";
	print "\t--nopublish Use d:\\numbers_test.txt for numbers and disable publishing\n";
	exit(0);
}

if ($sFbfProjectDir and $bPublish)
{
	print "Error: Option --projectdir requires --nopublish\n";
	exit(0);
}

if ($sFbfConfigDir and $bPublish)
{
	print "Error: Option --configdir requires --nopublish\n";
	exit(0);
}

my $sFbfProjectRev = '';
if ($sFbfProjectRepo =~ m,(.*)#(.*),)
{
	$sFbfProjectRepo = $1;
	$sFbfProjectRev = $2;
}
my $sFbfConfigRev = '';
if ($sFbfConfigRepo =~ m,(.*)#(.*),)
{
	$sFbfConfigRepo = $1;
	$sFbfConfigRev = $2;
}

my $sTestBuildOpt = "";
$sTestBuildOpt = "-Dsf.spec.publish.diamonds.category=package.test" if ( $bTestBuild );
my $sNoPublishOpt = "";
$sNoPublishOpt = "-Dsf.spec.publish.enable=false" if ( !$bPublish );
$sNUMBERS_FILE = "d:\\numbers_test.txt" if ( !$bPublish );

my $sLabelBaseString = $sFbfProjectRepo;
$sLabelBaseString = $sFbfProjectDir if ($sFbfProjectDir);
$sLabelBaseString =~ m,.*[\\/]([^\\^/]+),;
my $sJobLabel = $1;
$sJobLabel = $sLabelBaseString if (! $1);
mkdir($sJOB_BASE_DIR) if (!-d$sJOB_BASE_DIR);
my $sJobDir = mkdir_unique("$sJOB_BASE_DIR\\$sJobLabel");
print "Created project dir $sJOB_BASE_DIR\\$sJobLabel\n";

print("cd $sBOOTSTRAP_DIR\n");
chdir("$sBOOTSTRAP_DIR");
print "###### BOOTSTRAP ######\n";
my $sConfigArg = "-Dsf.config.repo=$sFbfConfigRepo";
$sConfigArg .= " -Dsf.config.rev=$sFbfConfigRev" if ($sFbfConfigRev);
$sConfigArg = "-Dsf.config.dir=$sFbfConfigDir" if ($sFbfConfigDir);
my $sProjectArg = "-Dsf.project.repo=$sFbfProjectRepo";
$sProjectArg .= " -Dsf.project.rev=$sFbfProjectRev" if ($sFbfProjectRev);
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

my $nUnformattedNumber = 0;
if ($nCmdLineNumber)
{
	$nUnformattedNumber = $nCmdLineNumber;
}
elsif ($sFbfProjectRepo)
{
	my $sRevZeroHash = get_rev_zero_hash($sFbfProjectRepo);
	my $sJobNumberKey = $sRevZeroHash;
	$sJobNumberKey .= ".T" if ($bTestBuild);
	$nUnformattedNumber = get_job_number($sJobNumberKey);
}
my $nJobNumber = sprintf("%.3d", $nUnformattedNumber);
$nJobNumber = "T$nJobNumber" if ($bTestBuild);

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
print("hlm sf-prep -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpt $sNoPublishOpt\n");
system("hlm sf-prep -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpt $sNoPublishOpt");

print "###### EXECUTE BUILD ######\n";
print("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpt $sNoPublishOpt\n");
system("hlm sf-build-all -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTestBuildOpt $sNoPublishOpt");

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

sub get_rev_zero_hash
{
	my ($sFbfProjectRepo) = @_;
	
	my $sOutput = `hg -R $sFbfProjectRepo identify -r0`;
	
	# remove leading and trailing spaces
	$sOutput =~ s,^\s+,,;
	$sOutput =~ s,\s+$,,;
	
	# remove tags e.g. "1fc39a7e9d79 tip"
	$sOutput =~ s,([0-9a-z]+)\s+.*,$1,;
	
	return $sOutput;
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
