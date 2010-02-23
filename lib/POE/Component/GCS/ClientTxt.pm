# -*- Perl -*-
#
# File:  POE/Component/GCS/ClientTxt.pm
# Desc:  Text-based version of client module to access GCS server
# Date:  Thu Sep 29 11:34:52 2005
# Stat:  Production release
# Note:  Documentation is provided after the end of this module.
#
# Note:  For better performance, this module uses the "IO::Socket" 
#        class to communicate with the command server daemon. To
#        experiment with messaging, use the 'PoCo::GCS::ClientMsg' 
#        class. That module uses the 'PoCo::GCS::Server::Msg' class
#        and, as a result, performance is somewhat less.
#
package POE::Component::GCS::ClientTxt;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.04';
### @ISA     = qw( );

use IO::Socket;

# Note:  port 23456 runs a 'message based' socket listener
#        port 23457 runs a 'plain text' socket listener
#
my($Host,$Port) = ('localhost', 23457);
my $ServerName  = "GCS Server";

my($CR,$LF,$CRLF) = ("\015","\012","\015\012"); # socket protocol

sub send
{   my($class,$msgText,$host,$port) = @_;

    (defined($msgText) and length($msgText)) or return (1,"nothing to send");

    $host     ||= $Host;
    $port     ||= $Port;

    my($status,$response);

    my $sock = new IO::Socket::INET( 'PeerAddr' => $host,
                                     'PeerPort' => $port,
                                     'Proto'    => 'tcp', )
	or return (-1, "$! -- is $ServerName running? ('$host:$port')");

    print $sock "$msgText$CRLF";                  # send the message

    while ( my $line = <$sock>) {                 # read the results
	if ($line =~ /^:?GCS_Status:(-?\d+)/) {   # watch for status line
	    $status = $1;
	    next;
	}
        last if ($line =~ /^:GCS_EOD:/);          # watch for terminator
	$response .= $line;                       # accumulate results
    }
    $sock->shutdown(2);                           # proper socket etiquette:
    $sock->close();                               #  a shutdown then a close.

    # print "DEBUG: stat='$status' response='$response'\n";        # DEBUG

    chomp($response)  if $response;

    return( $response ) unless wantarray;
    return( $status, $response );
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::ClientTxt - Text-based client to access Generic Server

=head1 VERSION

This document describes version 0.01, released November, 2005.

=head1 SYNOPSIS

  use POE::Component::GCS::ClientTxt;
  $gcsClient = "POE::Component::GCS::ClientTxt";

  ($stat, $response) = $gcsClient->send( $command, [,$host] [,$port] );

  $stat and die $response;
  print $response;


=head1 DESCRIPTION

This class is a generic client interface to a generic server process.
The intent is for this to be used as a starting point when building
network client/server applications.

=head2 Constructor

None. This module provides only class methods.

=head2 Methods

=over 4

=item send ( Command [, Host ] [, Port ] )

This method is used to B<send> a command to the generic server process 
that is expected to be running on the local host.

=over 4

=item Command

This required parameter specifies the B<Command> passed to the server,
and must be in a format that the server is designed to recognize as valid.

=item Host

The optional parameter is the name of the generic server.
This defaults to a value of 'localhost'.

=item Port

The optional parameter is the port number of the generic server.
This defaults to a value of 'nnnn'.

=back

=item stat

This return value from the B<send> method indicates the 
success (0) or failure (non-zero) of the command sent.

=item response

This return value from the B<send> method will be either the 
successful response (when status equals zero) or an error message 
(when status is non-zero).

=back

=head1 DEPENDENCIES

This class depends upon the following classes:

 IO::Socket
 POE::Component::GCS::Server::Msg
 POE::Event::Message

=head1 SEE ALSO

See L<POE::Component::GCS::Server>,
    L<POE::Component::GCS::Server::Msg> and
    L<POE::Event::Message>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
