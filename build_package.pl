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
my $sJOB_BASE_DIR="fbf_project";
my $nMAX_JOBDIR_AGE_SECONDS = 86400; # max number of seconds after which the letter is forcibly released
my $nLOCK_FILE_MAX_ATTEMPTS = 5;
my $sNUMBERS_FILE="\\\\v800020\\Publish\\SF_builds\\numbers.txt";
my $sLETTERS_FILE="letters.txt";
my $nMAX_LETTER_AGE_SECONDS = 86400; # max number of seconds after which the letter is forcibly released

my $sFbfProjectRepo = "http://developer.symbian.org/oss/MCL/sftools/fbf/projects/packages";
my $sFbfProjectDir = '';
my $sSubProject = '';
my $sSubprojVariant = '';
my $sSourcesRevision = '';
my $sSBSConfig = '';
#my $sSourcesFile = '';
#my $sModelFile = '';
my $sFbfConfigRepo="http://developer.symbian.org/oss/MCL/sftools/fbf/configs/default";
my $sFbfConfigDir = '';
my $nCmdLineNumber;
my $sDiamondsTag = '';
my $bHudson = 0;
my $bPublish = 1;
my %hHlmDefines = ();
my $bDisableAntiVirus = 0;
my $sUseBom = '';
my $bHelp = 0;
GetOptions((
	'configrepo=s' => \$sFbfConfigRepo,
	'configdir=s' => \$sFbfConfigDir,
	'projectrepo=s' => \$sFbfProjectRepo,
	'projectdir=s' => \$sFbfProjectDir,
	'subproj=s' => \$sSubProject,
	'variant=s' => \$sSubprojVariant,
	'sourcesrev=s' => \$sSourcesRevision,
	'sbsconfig=s' => \$sSBSConfig,
	#'sources=s' => \$sSourcesFile,
	#'model=s' => \$sModelFile,
	'number=s' => \$nCmdLineNumber,
	'tag=s' => \$sDiamondsTag,
	'hudson!' => \$bHudson,
	'publish!' => \$bPublish,
	'define=s' => \%hHlmDefines,
	'disableav!' => \$bDisableAntiVirus,
	'bom=s' => \$sUseBom,
	'help!' => \$bHelp
));

if ($bHelp or !($sSubProject or $sFbfProjectRepo or $sFbfProjectDir))
{
	print "Usage: build_package.pl --subproj=RELPATH [OPTIONS]\n";
	print "       build_package.pl --projectrepo=REPO [OPTIONS]\n";
	print "where OPTIONS are:\n";
	print "\t--subproj=RELPATH Select subproject located at RELPATH (relative to the root of the project repository)\n";
	print "\t--variant=VARIANT If specified use sources_VARIANT.csv instead of sources.csv and add \"VARIANT\" as tag for this build\n";
	print "\t--sourcesrev=REV Sync source repos at revision REV (overrides the revision specified in sources.csv). Note this is the same for all source repos.\n";
	print "\t--sbsconfig=CONFIG Pass on CONFIG as configuration to SBS (can also be a comma separated list, e.g. 'armv5,winscw')\n";
	print "\t--projectrepo=REPO[#REV] Use repository REPO at revision REV for the project (instead of http://developer.symbian.org/oss/MCL/sftools/fbf/projects/packages)\n";
	print "\t--projectdir=DIR Use DIR location for the project (exclusive with --projectrepo).\n";
	#print "\t--sources=FILE ...\n";
	#print "\t--model=FILE ...\n";
	print "\t--configrepo=REPO[#REV] Use repository REPO at revision REV for the config (instead of http://developer.symbian.org/oss/MCL/sftools/fbf/configs/default)\n";
	print "\t--configdir=DIR Use DIR location for the config (exclusive with --configrepo).\n";
	print "\t--number=N Force build number to N\n";
	print "\t--tag=TAG Apply Diamonds tag TAG to this build\n";
	print "\t--hudson Clean up all job dirs after the build)\n";
	print "\t--nopublish Use \\numbers_test.txt for numbers and disable publishing\n";
	print "\t--define ATTRIBUTE=VALUE Pass -D statements to the Helium Framework\n";
	print "\t--disableav Disable Anti-Virus for the duration of the build (also sync with other concurrent package builds)\n";
	print "\t--bom=LOCATION Use to build by taking the sources.csv from the build_BOM.zip at LOCATION\n";
	exit(0);
}

if ($sSubProject and $sSubProject !~ m,^([^/]+)/[^/]+/([^/]+)$,)
{
	print "ERROR: Option --subproj must be in the format codeline/layer/package (e.g. MCL/os/boardsupport)\n";
	exit(0);
}

#if (!$sFbfProjectRepo and !$sFbfProjectDir and (!$sSourcesFile or !$sModelFile))
#{
#	print "Error: If you don't provide --projectrepo or --projectdir then you have to provide both --sources and --model\n";
#	exit(0);
#}

my $sWORKING_DRIVE = find_working_drive();
print "Will use drive $sWORKING_DRIVE as working drive for this build\n";

# check that $sLETTERS_FILE exists, otherwise create it
if (!-f "$sWORKING_DRIVE\\$sLETTERS_FILE")
{
	open FILE, ">$sWORKING_DRIVE\\$sLETTERS_FILE";
	print FILE "\n";
	close FILE;
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

my $sHlmDefineOpt = '';
for (keys %hHlmDefines)
{
	$sHlmDefineOpt .= "-D$_=$hHlmDefines{$_} ";
}

my $sNoPublishOpt = "";
$sNoPublishOpt = "-Dsf.spec.publish.enable=false" if ( !$bPublish );
$sNUMBERS_FILE = "$sWORKING_DRIVE\\numbers_test.txt" if ( !$bPublish );

my $sJobLabel = 'job';
if ($sSubProject)
{
	$sSubProject =~ m,^([^/]+)/[^/]+/([^/]+)$,;
	$sJobLabel = $2;
}
elsif ($sFbfProjectRepo)
{
	$sFbfProjectRepo =~ m,(.*[\\/])?([^\\^/]+),;
	$sJobLabel = $2;
}
elsif ($sFbfProjectDir)
{
	$sFbfProjectDir =~ m,(.*[\\/])?([^\\^/]+),;
	$sJobLabel = $2;
}
#elsif ($sSourcesFile)
#{
#	$sSourcesFile =~ m,/(adaptation|app|mw|os|ostools|tools)[\\/]([^\\^/]+),i;
#	$sJobLabel = $2;
#	$sSourcesFile =~ m,(.*[\\/])?([^\\^/]+),;
#	$sJobLabel = $2 if (!$sJobLabel);
#}
mkdir("$sWORKING_DRIVE\\$sJOB_BASE_DIR") if (!-d "$sWORKING_DRIVE\\$sJOB_BASE_DIR");
my $sJobDir = mkdir_unique("$sWORKING_DRIVE\\$sJOB_BASE_DIR\\$sJobLabel");
print "Created project dir $sJobDir\n";

print("cd $sBOOTSTRAP_DIR\n");
chdir("$sBOOTSTRAP_DIR");
print "###### BOOTSTRAP ######\n";
my $sConfigArg = "-Dsf.config.repo=$sFbfConfigRepo";
$sConfigArg .= " -Dsf.config.rev=$sFbfConfigRev" if ($sFbfConfigRev);
$sConfigArg = "-Dsf.config.dir=$sFbfConfigDir" if ($sFbfConfigDir);
my $sProjectArg = "-Dsf.project.repo=$sFbfProjectRepo";
$sProjectArg .= " -Dsf.project.rev=$sFbfProjectRev" if ($sFbfProjectRev);
$sProjectArg = "-Dsf.project.dir=$sFbfProjectDir" if ($sFbfProjectDir);
my $sBootstrapCmd = "hlm -f bootstrap.xml $sConfigArg $sProjectArg -Dsf.target.dir=$sJobDir";
print("$sBootstrapCmd\n");
system($sBootstrapCmd);

# get sources.csv from supplied BOM location
if ($sUseBom)
{
  print("get sources.csv from supplied BOM location\n");
  my $sGetSourcesCmd = "7z e -y -i!build_info\\logs\\BOM\\sources.csv -o$sJobDir\\build\\config\\$sSubProject $sUseBom\\build_BOM.zip";
  print("$sGetSourcesCmd\n");
  system($sGetSourcesCmd);
}

# check that $sNUMBERS_FILE exists, otherwise create it
if (!-f $sNUMBERS_FILE)
{
	open FILE, ">$sNUMBERS_FILE";
	print FILE "\n";
	close FILE;
}

my $sJobNumberKey = '';
my $sPackage = '';
my $sPlatform = '';
my $nUnformattedNumber = 0;
if ($nCmdLineNumber)
{
	$nUnformattedNumber = $nCmdLineNumber;
}
elsif ($sFbfProjectRepo)
{
	if ($sSubProject)
	{
		# key = <package>_<codeline>, e.g. for subproj=MCL/os/boardsupport -> key=boardsupport_MCL
		$sSubProject =~ m,^([^/]+)/[^/]+/([^/]+)$,;
		$sPackage = $2;
		$sPlatform = $1;
		$sJobNumberKey = "$2_$1";
	}
	else
	{
		# key = hash of the rev.0 of the package project repo
		my $sRevZeroHash = get_rev_zero_hash($sFbfProjectRepo);
		$sJobNumberKey = $sRevZeroHash;
	}
	$nUnformattedNumber = get_job_number($sJobNumberKey);
}
my $nJobNumber = sprintf("%.3d", $nUnformattedNumber);
print "For build key $sJobNumberKey got assigned number \"$nJobNumber\"\n";

# acquire drive letter
my $sDriveLetter = acquire_drive_letter();
die "Could not acquire drive letter" if (!$sDriveLetter);
print "acquired drive letter: $sDriveLetter\n";

# disable antivirus:
# done after the acquisition of the drive letter as letter file
# is used as a means to sync with concurrent package builds
if ($bDisableAntiVirus)
{
	print "disabling anti-virus\n";
	my $disableav_cmd = "av.bat /stop";
	print "$disableav_cmd\n";
	system($disableav_cmd);
}

my $sJobRootDirArg = "-Dsf.spec.job.rootdir=$sWORKING_DRIVE\\fbf_job";

my $sSubProjArg = '';
$sSubProjArg = "-Dsf.subproject.path=$sSubProject" if ($sSubProject);
my $sVariantArg = '';
$sVariantArg = "-Dsf.spec.sourcesync.sourcespecfile=sources_$sSubprojVariant.csv" if ($sSubprojVariant);
my $sSourcesRevisionArg = '';
$sSourcesRevisionArg = "-Dsf.spec.sources.revision=\"$sSourcesRevision\"" if ($sSourcesRevision);
my $sSBSConfigArg = '';
$sSBSConfigArg = "-Dsf.spec.sbs.config=\"$sSBSConfig\"" if ($sSBSConfig);
my $sAllTags = '';
$sAllTags = $sDiamondsTag if ($sDiamondsTag);
$sAllTags .= ',' if ($sAllTags and $sSubprojVariant);
$sAllTags .= $sSubprojVariant if ($sSubprojVariant);
my $sTagsArg = "";
$sTagsArg = "-Dsf.spec.publish.diamonds.tag=\"$sAllTags\"" if ($sAllTags);
print("cd $sJobDir\\sf-config\n");
chdir("$sJobDir\\sf-config");
print "###### BUILD PREPARATION ######\n";
my $sPreparationCmd = "hlm sf-prep -Dsf.project.type=package $sSubProjArg -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTagsArg $sNoPublishOpt $sJobRootDirArg $sHlmDefineOpt $sVariantArg $sSourcesRevisionArg $sSBSConfigArg";
print("$sPreparationCmd\n");
system($sPreparationCmd);

print "###### EXECUTE BUILD ######\n";
my $sBuildallCmd = "hlm sf-build-all -Dsf.project.type=package $sSubProjArg -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTagsArg $sNoPublishOpt $sJobRootDirArg $sHlmDefineOpt $sVariantArg $sSourcesRevisionArg $sSBSConfigArg";
print("$sBuildallCmd\n");
system($sBuildallCmd);

print "###### FINALIZE BUILD ######\n";
my $sFinalizeCmd = "hlm sf-finalize -Dsf.project.type=package $sSubProjArg -Dsf.spec.job.number=$nJobNumber -Dsf.spec.job.drive=$sDriveLetter: $sTagsArg $sNoPublishOpt $sJobRootDirArg $sHlmDefineOpt $sVariantArg $sSourcesRevisionArg $sSBSConfigArg";
print("$sFinalizeCmd\n");
system($sFinalizeCmd);

print("cd $sBOOTSTRAP_DIR\n");
chdir("$sBOOTSTRAP_DIR");

# release the drive letter and optionally re-enable the AV
release_drive_letter_and_reenable_av($sDriveLetter);
system("subst $sDriveLetter: /d"); # this is not required, but it's a good idea to keep things in order
print "drive letter $sDriveLetter released (and drive unsubsted)\n";

if ($bHudson)
{
	print "cleaning job directories...\n";
	if (-d "$sWORKING_DRIVE\\$sJOB_BASE_DIR\\$sJobLabel") # project dir
	{
		print "rmdir /S /Q $sJobDir\n";
		system("rmdir /S /Q $sJobDir");
	}
	if (-d "$sWORKING_DRIVE\\fbf_job\\$sPackage\_$sPlatform.$nJobNumber") # build drive
	{
		print "rmdir /S $sWORKING_DRIVE\\fbf_job\\$sPackage\_$sPlatform.$nJobNumber\n";
		system("rmdir /S /Q $sWORKING_DRIVE\\fbf_job\\$sPackage\_$sPlatform.$nJobNumber");
	}
}

sub find_working_drive
{
	my @drive_list = ('E', 'G', 'D', 'C');
	
	for my $drive (@drive_list)
	{
		return "$drive:" if (-d "$drive:/");
	}
	
	die "Could not find suitable working drive.";
}

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
		open(FILE, "+<$sWORKING_DRIVE\\$sLETTERS_FILE") or die("Can't open $sWORKING_DRIVE\\$sLETTERS_FILE");
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
					
					if (time()-$nTimestamp<=$nMAX_LETTER_AGE_SECONDS or $nTimestamp == 0 or $nTimestamp == -1)
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

sub release_drive_letter_and_reenable_av
{
	my ($sLetterToRelease) = @_;
	
	my %hsPidsAndTimestamps = ();
	
	my $nAttempts = 0;
	my $bAcquired = 0;
	do
	{
		open(FILE, "+<$sWORKING_DRIVE\\$sLETTERS_FILE") or die("Can't open $sWORKING_DRIVE\\$sLETTERS_FILE");
		if ( flock(FILE, 6) )
		{
			my $sLine;
			while ($sLine = <FILE>)
			{
				$hsPidsAndTimestamps{$1} = $2 if ($sLine =~ m%([^,]*),(.*)%);
			}
			
			delete $hsPidsAndTimestamps{$sLetterToRelease};
			
			seek(FILE, 0, 0);
			
			# if there are no other builds at this time then enable back the antivirus
			my $nConcurrentBuilds = scalar(keys(%hsPidsAndTimestamps));
			if ($nConcurrentBuilds == 0)
			{
				if ($bDisableAntiVirus)
				{
					print "enabling anti-virus\n";
					my $enableav_cmd = "av.bat /start";
					print "$enableav_cmd\n";
					system($enableav_cmd);
				}
			}

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
