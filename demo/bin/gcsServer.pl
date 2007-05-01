#!/opt/perl/bin/perl -T
#
# File:  gcsServer.pl
# Desc:  Script to start a GCS server process
# Date:  Fri Mar 23 13:23:10 2007
# Stat:  Prototype, Experimental
#
# Synopsis:
#        gcsServer.pl -h
#
use Cwd;
BEGIN {  # Script is relocatable. See http://ccobb.net/ptools/
  my $cwd = $1 if ( $0 =~ m#^(.*/)?.*# );  chdir( "$cwd/.." );
  my($top,$app)=($1,$2) if ( getcwd() =~ m#^(.*)(?=/)/?(.*)#);
  $ENV{'PTOOLS_TOPDIR'} = $top;  $ENV{'PTOOLS_APPDIR'} = $app;
} #-----------------------------------------------------------
use PTools::Local;          # PTools local/global vars/methods

# Note: Using a config file is optional
#
my $configFile = PTools::Local->path('app_cfgdir', "gcs/gcs.conf"); 

use POE::Component::GCS::Server;
exit( run POE::Component::GCS::Server( $configFile ) );
