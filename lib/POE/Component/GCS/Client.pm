# -*- Perl -*-
#
# File:  POE/Component/GCS/Client.pm
# Desc:  GCS client: Generic clienet/server model
# Date:  Fri Mar 23 13:35:05 2007
# Stat:  Prototype
#
# Abstract
#        This is a simple command-line client interface to a
#        running GCS Server process. Create a small script to
#        use this module as shown next. Run the small script
#        with a "-h" option to see usage syntax. Note that there
#        are several additional usage options that are useful to
#        exercise/verify various server components. 
#
# Module Synopsis:
#        #!/opt/perl/bin/perl
#
#        use POE::Component::GCS::Client qw( Text-based );
#  -or-  use POE::Component::GCS::Client qw( Msg-based );
#
#        exit( run POE::Component::GCS::Client );
#
# Command Synopsis:
#        Usage: cmd  ping            # access 'Command' service
#               cmd  sleep <n>       # access 'Housekeeping' service
#               cmd  echo <text>     # access 'Control/Maintenance'
#               cmd  banner <text>   # access 'Control/Maintenance'
#               cmd  help            # show list of valid commands
#

package POE::Component::GCS::Client;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.01';
our @ISA     = qw( );

use POE::Component::GCS::ClientMsg;       # Message-based client module
use POE::Component::GCS::ClientTxt;       # Text-based client module
use POE::Component::GCS::Server::Cfg;     # Server port num config
use PTools::Local;                        # Local/global vars, etc.

my $GCSClient;      # client class is determined via 'import' method
## $GCSClient = "POE::Component::GCS::ClientMsg";
## $GCSClient = "POE::Component::GCS::ClientTxt";
my $CfgClass  = "POE::Component::GCS::Server::Cfg";

my($Host, $Port);

sub import
{   my($class,$mode,$port,$host) = @_;

    my $cfgFile = PTools::Local->path('app_cfgdir', "gcs/gcs.conf");
    my $config  = $CfgClass->new( $cfgFile );
    $Host       = $host || 'localhost';

    if ( ($mode) and ($mode =~ m#^(Msg|Message)#) ) {

	$Port = $port || $config->get('MsgPort') || 23456;
	$GCSClient = "POE::Component::GCS::ClientMsg";

    } else {

	$Port = $port || $config->get('TxtPort') || 23457;
	$GCSClient = "POE::Component::GCS::ClientTxt";
    }
    return;
}

*new = \&send;
*run = \&send;

sub send
{   my($class,@args) = @_;

    if ($ARGV[0] and $ARGV[0] =~ m#(-h|--help)#) {
        my $baseName = PTools::Local->get('basename');
	warn "\n Usage:  $baseName <args>\n";
	warn "\n    where <args> can include \n";
	warn "       -h     - display this help message and exit\n";
	warn "       help   - display synopsis of server commands\n";
	warn "       <cmd>  - send cmd/arg(s) to server daemon\n\n";
	exit(0);
    }

    my($stat,$response) = $GCSClient->send( "@ARGV", $Host, $Port );

    if ($response) {
	print $response;
	print "\n" unless $response =~ m#\n$#;
    }

    return( $stat ||0 );
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Client - Client demo to access GCS server

=head1 VERSION

This document describes version 0.01, released Mar, 2007.

=head1 SYNOPSIS

=head2 Module Synopsis

Create a small script to use this module. The 'B<gcsClient>' command, as 
shown here, is a complete implementation of this module. Exempli gratia:

 #!/opt/perl/bin/perl -T
 #
 use POE::Component::GCS::Client qw( Text-based );   # use one or the
 ### POE::Component::GCS::Client qw( Msg-based );    # other, not both

 exit( run POE::Component::GCS::Client );        # return status to OS

=head2 Command Synopsis

Run the small script, created as shown above, using the '-h' (or '--help') 
command line option for usage help. To see a list of valid I<server> 
commands, run script with the 'help' command.

 Usage: gcsClient <your added command here>

=head2 Test/Debug Synopsis

 Usage: gcsClient  ping            # access 'Cmd' service
        gcsClient  sleep <n>       # access 'Task' service
        gcsClient  echo <text>     # access 'Queue/Proc' service
        gcsClient  banner <text>   # access 'Queue/Proc' service
        gcsClient  myCmd <text>    # example of adding custom cmd
        gcsClient  help            # show list of server commands

 These additional commands can be used to access/test/demo various
 internal components of the TempViewManager server.


=head1 DESCRIPTION

This class is a client interface to the GCS server.
This is intended to be implemented via a script named 'B<gcsClient>' and 
used used as a demo of a I<selectable> interface.

There are currently two different interfaces to the GCS server. A
B<Text-based> client will use simple text to communicate with the
server. A B<Message-based> client can be used to pass a Perl
object with the 'server command' as the message body.

The Text-based client has better performance under volume usage, 
while the Message-based client has more flexibility.


=head1 DEPENDENCIES

This script depends upon the following classes:

 POE::Component::GCS::ClientMsg     # GCS Msg-based TCP client module
 POE::Component::GCS::ClientTxt     # GCS Txt-based TCP client module
 POE::Component::GCS::Server::Cfg   # GCS Server configuration module

=head1 SEE ALSO

 L<POE::Component::GCS::ClientMsg>,
 L<POE::Component::GCS::ClientTxt> and
 L<POE::Component::GCS::Server>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
