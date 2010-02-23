# -*- Perl -*-
#
# File:  POE/Component/GCS/ClientMsg.pm
# Desc:  Message-based client module to access GCS server
# Date:  Thu Sep 29 11:34:52 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::ClientMsg;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.03';
### @ISA     = qw( );

use IO::Socket;                          # Don't use POE: Socket is faster
### POE::Event::Message;                 # application messaging class
use POE::Component::GCS::Server::Msg;    # application messaging class

# Note:  port 23456 runs a 'message based' socket listener
#        port 23457 runs a 'plain text' socket listener
#
my($LocalHost,$LocalPort) = ('localhost', 23456);
my $MsgClass = "POE::Component::GCS::Server::Msg";

*route = \&send;

sub send
{   my($class,$msgBody,$host,$port,$msgClass) = @_;

    (defined($msgBody) and length($msgBody)) or return (1,"nothing to send");

    $host     ||= $LocalHost;
    $port     ||= $LocalPort;
    $msgClass ||= $MsgClass;

    #-------------------------------------------------------------------
    # Example of using a remote routing with a message. The 
    # "sync" argument indicates we expect a synchronous reply 
    # (Meaning that the "$response" will be an actual "response"
    # message from the server).
    #
    # With an argument of "asynch", the message is sent and the
    # response message will have an empty body with a status
    # of "0", if successful, and a header message set to
    # "message sent successfully" -- it might be necessary to
    # first use the "addRemoteRouteBack()" method and add an
    # appropriate response destination (but only if necessary).
    # So, 'asynch' used here means "$response" will ONLY be an 
    # indication of whether or not a message was SENT successfully.

    my $msg = $msgClass->package( $msgBody );        # create envelope

    $msg->addRemoteRouteTo( $host, $port, "sync" );  # for immediate reply
 ###$msg->addRemoteRouteTo( $host, $port, "async");  # delayed or no reply

    my($response) = $msg->route();                   # route/get response

    unless (ref $response and $response->can('stat')) {
	die "Internal Error: Invalid response object: '$response'";
    }
    my $status = $response->stat();                  # check status
    #-------------------------------------------------------------------

    # In this example, for "sync" routing, "$respBody" will be
    # either an error or whatever was returned from the server:
    my $respBody = ($status ? $response->err() : $response->body() );

  ### In this example, for "async" routing, "$respBody" will be 
  ### either an error or the text "message sent successfully":
  # my $respBody = ($response->err() ? $response->err() : $response->body() );

    # print $msg->dump();                       # DEBUG
    # print $response->dump();                  # DEBUG

    return( $respBody ) unless wantarray;       # body of message only
    return( $status, $respBody );               # status and body
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::ClientMsg - Message-based client to access GCS  server

=head1 VERSION

This document describes version 0.01, released November, 2005.

=head1 SYNOPSIS

 use POE::Component::GCS::ClientMsg;

 $client = "POE::Component::GCS::ClientMsg";

 ($stat, $response) = $client->send( $command [,$host] [,$port] );

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
