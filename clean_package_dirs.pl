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
# This is a helper script which cleans up some space on the machine by
# removing old package-build-related directories 

use strict;

use Getopt::Long;
use File::Path;

my $sJOB_BASE_DIR = "D:\\fbf_job";
my $nJOB_MAX_DIR_AGE_SECS = 259200; # 259200=3 days
my $bJOB_SAVE_LAST_DIR = 1;

my $sPROJECT_BASE_DIR = "D:\\fbf_project";
my $nPROJECT_MAX_DIR_AGE_SECS = 259200; # 259200=3 days
my $bPROJECT_SAVE_LAST_DIR = 1;

my $nNow = time();

print "#### Cleaning old job dirs. ####\n";
opendir(DIR, "$sJOB_BASE_DIR");
my @asDirs = readdir(DIR);
close(DIR);

for my $sDir ( @asDirs )
{
	next if ( $sDir eq "." or $sDir eq ".." );
	next if ( ! -d "$sJOB_BASE_DIR\\$sDir" );
	
	#print "--- $sDir\n";
	
	if ( $sDir =~ /^([^.]+)\.T?(\d+)/ )
	{
		my $sBaseName = $1;
		my $sBuildNumber = $2;
		
		my $nTs = (stat("$sJOB_BASE_DIR\\$sDir"))[9]; # modified time
			
		my $bLastDir = 0;
		if ( $bJOB_SAVE_LAST_DIR )
		{
			my @asSimilarDirs = grep(/^$sBaseName(\.|$)/, @asDirs);
			$bLastDir = 1;
			for my $sSimilarDir ( @asSimilarDirs )
			{
				my $nSimDirTs = (stat("$sJOB_BASE_DIR\\$sSimilarDir"))[9];
				$bLastDir = 0 if ( $nSimDirTs > $nTs );
			}
			$bLastDir = 1 if ( ! scalar @asSimilarDirs );
		}
		
		if ( $bJOB_SAVE_LAST_DIR && $bLastDir )
		{
			print "Skipping $sDir as last dir in the series\n";
		}
		elsif ( $nNow - $nTs > $nJOB_MAX_DIR_AGE_SECS )
		{
			print "Removing $sDir...\n";
			print "rmdir /S $sJOB_BASE_DIR\\$sDir\n";
			system("rmdir /S /Q $sJOB_BASE_DIR\\$sDir");
		}
		else
		{
			print "Keeping $sDir\n";
		}
	}
	else
	{
		print "$sDir doesn't match\n";
	}
}

print "#### Cleaning old project dirs. ####\n";
opendir(DIR, "$sPROJECT_BASE_DIR");
@asDirs = readdir(DIR);
close(DIR);

for my $sDir ( @asDirs )
{
	next if ( $sDir eq "." or $sDir eq ".." );
	next if ( ! -d "$sPROJECT_BASE_DIR\\$sDir" );
	
	if ( $sDir =~ /^([^.]+)\.(\d+)/ or $sDir =~ /^([^.]+)$/ )
	{
		my $sBaseName = "";
		my $sBuildNumber = 0;
		if ( $sDir =~ /^([^.]+)\.(\d+)/ )
		{
			$sBaseName = $1;
			$sBuildNumber = $2;
		}
		elsif ( $sDir =~ /^([^.]+)$/ )
		{
			$sBaseName = $1;
		}
		
		my $nTs = (stat("$sPROJECT_BASE_DIR\\$sDir"))[9]; # modified time
		
		my $bLastDir = 0;
		if ( $bPROJECT_SAVE_LAST_DIR )
		{
			my @asSimilarDirs = grep(/^$sBaseName(\.|$)/, @asDirs);
			$bLastDir = 1;
			for my $sSimilarDir ( @asSimilarDirs )
			{
				my $nSimDirTs = (stat("$sPROJECT_BASE_DIR\\$sSimilarDir"))[9];
				$bLastDir = 0 if ( $nSimDirTs > $nTs );
			}
			$bLastDir = 1 if ( ! scalar @asSimilarDirs );
		}
		
		if ( $bPROJECT_SAVE_LAST_DIR && $bLastDir )
		{
			print "Skipping $sDir as last dir in the series\n";
		}
		elsif ( $nNow - $nTs > $nPROJECT_MAX_DIR_AGE_SECS )
		{
			print "Removing $sDir...\n";
			print "rmdir /S $sPROJECT_BASE_DIR\\$sDir\n";
			system("rmdir /S /Q $sPROJECT_BASE_DIR\\$sDir");
		}
		else
		{
			print "Keeping $sDir\n";
		}
	}
	else
	{
		print "$sDir doesn't match\n";
	}
}
