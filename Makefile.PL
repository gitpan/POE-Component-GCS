# -*- Perl -*-
#
# File:  Makefile.PL
# Desc:  Make the makefile for POE::Component::GCS and friends
# Date:  Fri Mar 23 12:51:45 2007
#
use inc::Module::Install;  # Warn: mods to Makefile.pm/WriteAll.pm

name		'POE-Component-GCS';
author		'Chris Cobb [no dot spam at ccobb dot net]';
license 	'perl';
all_from	'lib/POE/Component/GCS/Server.pm';
tests		't/*/*/*.t t/*/*/*/*.t t/*/*/*/*/*.t';

# When building this distribution
## no_index	directory 	=> 'eg';   #  no eg's just yet...
build_requires	Test::More	=> 0;

# Standard modules needed
requires	POSIX		=> 0;
requires	strict		=> 0;
requires	warnings	=> 0;

# Additional modules needed
requires 	IO::Socket		=> 0;
requires 	POE			=> 0;
requires 	POE::Event::Message	=> 0.10;
requires 	PTools::Local		=> 0;
requires	Date::Format		=> 2.22;
requires 	Time::HiRes		=> 0;

WriteAll( meta => 0 );
