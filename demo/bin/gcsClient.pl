#!/opt/perl/bin/perl -T
#
# File:  gcsClient.pl
# Desc:  A generic client to interact with a running GCS Server
# Date:  Fri Mar 23 13:24:38 2007
# Stat:  Prototype, Experimental
#
# Synopsis:
#        gcsClient.pl -h
#
use Cwd;
BEGIN {  # Script is relocatable. See http://ccobb.net/ptools/
  my $cwd = $1 if ( $0 =~ m#^(.*/)?.*# );  chdir( "$cwd/.." );
  my($top,$app)=($1,$2) if ( getcwd() =~ m#^(.*)(?=/)/?(.*)#);
  $ENV{'PTOOLS_TOPDIR'} = $top;  $ENV{'PTOOLS_APPDIR'} = $app;
} #-----------------------------------------------------------
use lib "$ENV{'PTOOLS_TOPDIR'}/$ENV{'PTOOLS_APPDIR'}";
use PTools::Local;          # PTools local/global vars/methods

# use POE::Component::GCS::Client qw( Message-based );
  use POE::Component::GCS::Client qw( Text-based );

# Note: Using a config file is optional to run the client.
#
my $configFile = PTools::Local->path('app_cfgdir', "gcs/gcs.conf"); 

exit( run POE::Component::GCS::Client( $configFile ) );
