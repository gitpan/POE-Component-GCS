# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/LogDemo.pm
# Desc:  Simple example of creating a subclass from a GCS base class.
# Date:  Wed Feb 02 17:03:35 2005
# Stat:  Prototype, Experimental
#
# Supported server logging parameters:
#
#        o  Default system log level (3) is set via the "Cfg" class
#        o  Logging value on startup ("-l n") sets log level to "n"
#        o  Debug value on startup ("-D [n]") sets log level to "n"
#        o  Sending SIGUSR1 to server ("-logincr") adds 2 to log level
#        o  Sending SIGUSR2 to server ("-logdecr") subs 2 fr log level
#        o  Sending SIGINT to server ("-logreset") resets log level
#
package POE::Component::GCS::Server::LogDemo;
use 5.006;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.01';
our @ISA     = qw( POE::Component::GCS::Server::Log );

use POE::Component::GCS::Server::Log;
use PTools::Date::Format;

my $FmtClass= "PTools::Date::Format";
my $DateFmt = "%Y%m%d.%H:%M:%S";           # 20051221.21:05:39
#  $DateFmt = "%c";                        # 12/21/05 09:05:39
#  $DateFmt = "%a, %d-%b-%Y %I:%M:%S %p";  # Wed, 21-Dec-2005 09:05:39 pm
#  $DateFmt = "%d-%b-%Y %H:%M:%S";         # 21-Dec-2005 21:05:39
#  $DateFmt = "%Y%m%d %H:%M:%S";           # 20051221 21:05:39

sub formatDate { $FmtClass->time2str( $DateFmt, time() ) }
#_________________________
1; # Required by require()

__END__

Some suggestions for defining an application level logging strategy.
(accessed via GCS server "$Log->write( $level, $message );" syntax)

# Level  0   primary system log entries includes
#            -  server startup/shutdown notices
#            -  critical error situation notices (also sent via email)
#               +  "hard" system limits reached
#               +  etc...
#            -  any proc (maintenance) stderr output
#
#        1   secondary system log entries adds
#            -  "important" server event notices, such as
#               +  signals received (for "monitored" signals only)
#               +  this, that, etc...
#            -  all View Pool state changes
#            -  "auto-release" View cleanup notices, including
#               +  "No process" when first noticed
#               +  "Timeout" message, when View recycled (after delay)
#            -  command dispatch notices
#               +  command dispatch requests, with "client id" tag
#               +  command dispatch that is "ignored" for any reason
#                  (e.g., "shutdown" only valid from Housekeeping service)
#                  (e.g., "request" only valid from 'localhost', etc.)
#               +  command dispatch that fails for any reason
#               +  commands that fail for any reason
#
#        2   log level two is undefined at this time
#            -  
#
#        3   first information level adds           (DEFAULT LOG LEVEL)
#            -  occasional system stats entries
#                (hourly, IF system was accessed in that hour)
#            -  isn't that enough for default logging??
#
#    4 - 5   second information level adds
#            -  basic server connect/disconnect notices
#            -  more  command dispatch notices
#            -  basic task (housekeeping) cycle notices
#            -  basic queue (control) notices
#            -  basic proc (maintenance) notices
#            -  basic View Pool maint notices
#
#    6 - 7   third information level adds
#            -  more server connect/disconnect notices
#            -  additional command dispatch notices, if any
#            -  more task (housekeeping) cycle notices
#            -  more queue (control) notices
#            -  more proc (maintenance) notices
#            -  more View Pool maint notices
#
#    8 - 9   first troubleshooting level adds
#            - 
#
#  10 - 11   second troubleshooting level adds
#            - 
#
#  12 - 13   first debugging level adds
#            - 
#
#  14 - 15   second debugging level adds
#            -  selected POE event monitoring output
#            -  *WAY* too much data to be useful
#
