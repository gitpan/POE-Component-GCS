# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/TCP.pm
# Desc:  Generic network TCP service
# Date:  Thu Sep 29 11:48:32 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::TCP;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.05';
our @ISA     = qw( );

use POE qw( Component::Server::TCP  Filter::Reference );
use POE::Component::GCS::Server::Cfg;

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my($CmdClass, $LogClass, $MsgClass);
my($Cfg, $Log);
my($TxtPort,$MsgPort);
my $MsgAlias = "MsgServer";              # used by Cmd class for 'shutdown'
my $TxtAlias = "TxtServer";              # used by Cmd class for 'shutdown'


sub new { bless {}, ref($_[0])||$_[0]  }

sub spawn
{   my($self) = @_;

    $Cfg = $CfgClass->new();
    $CmdClass  = $Cfg->get('CmdClass') || die "No 'cmdclass' found here";
    $LogClass  = $Cfg->get('LogClass') || die "No 'logclass' found here";
    $MsgClass  = $Cfg->get('MsgClass') || die "No 'msgclass' found here";
    $MsgPort   = $Cfg->get('MsgPort')  || 0;
    $TxtPort   = $Cfg->get('TxtPort')  || 0;

    $Log       = $LogClass->new()      || die "Unable to access Log service";

    if ($MsgPort) {
	$self->createMsgServer()  
    } else {
        $Log->write(3, "$MsgAlias: no 'message' TCP service started");
    }

    if ($TxtPort) {
	$self->createTxtServer()  
    } else {
        $Log->write(3, "$TxtAlias: no 'text' TCP service started");
    }
    return;
}

#-----------------------------------------------------------------------
# Based on the server config file, we will attempt to create either
# one or two TCP servers here.
# .  a 'text-based' server will only work with plain text commands
# .  a 'message-based' server will work with 'POE::Event::Message' 
#    (or a subclass thereof) for communication
#
# Note that, either way, all INTERNAL communication in this server
# uses 'POE::Event::Message' objects (or a subclass)  routed to the 
# various events. With the 'text-based' server, these are converted 
# to/from plain text for communication with a 'text-based' client.
#-----------------------------------------------------------------------

sub createMsgServer
{   my($self) = @_;

    #-------------------------------------------------------------------
    # Msg-based TCP SERVER creation - expects Message-based I/O only
    #-------------------------------------------------------------------

    $Log->write(0, "$MsgAlias: spawning 'message' TCP service (port=$MsgPort)");

    my $filter = "POE::Filter::Reference";

    POE::Component::Server::TCP->new(
	Port     => $MsgPort,           # Required.     Bind Port
     ## Acceptor => \&accept_msg,       # Optional.     see ClientInput
     ## Error    => \&error_msg,        # Optional.
	Alias    => $MsgAlias,          # Optional.     (required by Cmd)

        ClientInput        => \&handle_msg_input,         # Required.
        ClientConnected    => \&handle_msg_connect,       # Optional.
        ClientDisconnected => \&handle_msg_disconnect,    # Optional.
     ## ClientError        => \&handle_msg_error,         # Optional.
     ## ClientFlushed      => \&handle_msg_flush,         # Optional.
        ClientFilter       => $filter,                    # Optional.
     ## ClientInputFilter  => "POE::Filter::Reference",   # Optional.
     ## ClientOutputFilter => "POE::Filter::Reference",   # Optional.
     ## ClientShutdownOnError => 0,                       # Optional.

	# Most of the events we need are pre-defined by POE. 
	# We add one here to so we can create a "routeback" 
	# event target to simplify the response mechanism.

	InlineStates => {
             client_msg_output => \&handle_msg_output,
	},
    );

    return;
}

sub createTxtServer
{   my($self) = @_;

    #-------------------------------------------------------------------
    # Txt-based TCP SERVER creation - expects plain text I/O only
    #-------------------------------------------------------------------

    $Log->write(0, "$TxtAlias: spawning 'text' TCP service (port=$TxtPort)");

    POE::Component::Server::TCP->new(
	Port     => $TxtPort,           # Required.     Bind Port
     ## Acceptor => \&accept_txt,       # Optional.     see ClientInput
     ## Error    => \&error_txt,        # Optional.
	Alias    => $TxtAlias,          # Optional.     (required by Cmd)

        ClientInput        => \&handle_txt_input,         # Required.
        ClientConnected    => \&handle_txt_connect,       # Optional.
        ClientDisconnected => \&handle_txt_disconnect,    # Optional.
     ## ClientError        => \&handle_txt_error,         # Optional.
     ## ClientFlushed      => \&handle_txt_flush,         # Optional.
     ## ClientFilter       => $filter,                    # Optional.
     ## ClientInputFilter  => "POE::Filter::Reference",   # Optional.
     ## ClientOutputFilter => "POE::Filter::Reference",   # Optional.
     ## ClientShutdownOnError => 0,                       # Optional.

	# Most of the events we need are pre-defined by POE. 
	# We add one here to so we can create a "routeback" 
	# event target to simplify the response mechanism.

	InlineStates => {
             client_txt_output => \&handle_txt_output,
	},
    );

    return;
}

#-----------------------------------------------------------------------
# Msg-based TCP SERVER event handler methods
#-----------------------------------------------------------------------

sub handle_msg_input
{   my($kernel, $heap, $session, $input) = @_[KERNEL, HEAP, SESSION, ARG0];

    my $sessionId = $session->ID;
    my $stateArgs = undef;

    # NOTE: Here $input is expected to be a "$MsgClass" object

    if (! ($input and ref($input) and $input->isa($MsgClass)) ) {
	# warn $reply->dump();            # DEBUG

	# WIP:
	$Log->write(0, "$MsgAlias: client request invalid (cid=$sessionId): input='$input'");
	$Log->write(0, "$MsgAlias: (expecting a '$MsgClass' object)");
	## $heap->{client}->put( "invalid command" );
	return;
    }

  #---------------------------------------------------------------------
  # Create a msg routeback wormhole. Use "post" for asynch delivery,
  # or "call" for immediate delivery that bypasses POE's event queue.
  # Note that with routebacks we can interrupt normal flow by adding
  # routing directives that the originator knows nothing about. This
  # will be handy if/when we have monitoring tools that watch events.
  #
    $input->addRouteBack( post => "", "client_msg_output", $stateArgs );

  ### $input->addRouteBack( post => "task", "bounce", $stateArgs );
  #---------------------------------------------------------------------

    $input->set('ClientId',   $sessionId           );
    $input->set('RemoteIp',   $heap->{remote_ip}   );
 ## $input->set('RemotePort', $heap->{remote_port} );

    #__________________________________________
    ## Server shutdown is initiated by the following:
    ##   $kernel->post( TCPServer => "shutdown" );
    ##
    ## FIX: Do we need to accomodate "shutdown" here??
    ## During shutdown POE will set a heap flag...

    ## if ($heap->{shutdown}) { ...do what?... }

    #__________________________________________
    ## FIX: currently "dispatch" is synchronous; Change this???
    ##
    $CmdClass->dispatch( $input );           # non-POE method

    $Log->write(4, "$MsgAlias: client request dispatched (cid=$sessionId)");

    return;
}

sub handle_msg_output
{   my($kernel, $heap, $session, $state_args, $result_args) =
    @_[ KERNEL,  HEAP,  SESSION,  ARG0,        ARG1       ];

    # This handler is the "routeback" target that returns data
    # to client ($reply is expected to be a "$MsgClass" object).
    # Here we simply return it to the waiting Msg-based client.

    my $reply = $result_args->[0];

    if ($reply and ref($reply) and $reply->isa($MsgClass)) {
	# warn $reply->dump();     # DEBUG

	$reply->del('ReplyTo');    # remove any residual CODE refs.
	$reply->del('ClientId');   # CID added above; remove it here.
        $reply->del('RemoteIp');   # IP added above; remove it here.
    }

    # The "client" attribute was added by POE to the heap to
    # facilitate sending the correct response to the correct 
    # client. All we need to do is "put" the "$reply".

    $heap->{client}->put( $reply );

  # my $stat = $heap->{client}->put( $reply );
  # my $chek = $!;
  # warn "DEBUG: PUT stat='$stat' chek='$chek'";

    my $sessionId = $session->ID;

    $Log->write(4, "$MsgAlias: client reply sent (cid=$sessionId)");
    return;
}

sub handle_msg_connect
{   my($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

    my $sessionId = $session->ID;
    $Log->write(4, "$MsgAlias: client connect (cid=$sessionId)");

    return;
}

sub handle_msg_disconnect
{   my($kernel,$heap, $session) = @_[KERNEL,HEAP,SESSION];

    my $sessionId = $session->ID;
    $Log->write(4, "$MsgAlias: client disconnect (cid=$sessionId)");

    return;
}

#-----------------------------------------------------------------------
# Txt-based TCP SERVER event handler methods
#-----------------------------------------------------------------------

sub handle_txt_input
{   my($kernel, $heap, $session, $input) = @_[KERNEL, HEAP, SESSION, ARG0];

    # NOTE: Here $input is expected to be "plain text"

    my $sessionId = $session->ID;
    my $stateArgs = undef;

    $input = $MsgClass->new( undef, $input );   # wrap input with message

  #---------------------------------------------------------------------
  # Create a msg routeback wormhole. Use "post" for asynch delivery,
  # or "call" for immediate delivery that bypasses POE's event queue.
  # Note that with routebacks we can interrupt normal flow by adding
  # routing directives that the originator knows nothing about. This
  # will be handy if/when we have monitoring tools that watch events.

    $input->addRouteBack( post => "", "client_txt_output", $stateArgs );

  ### $input->addRouteBack( post => "task", "bounce", $stateArgs );
  #---------------------------------------------------------------------

    $input->set('ClientId',   $sessionId           );
    $input->set('RemoteIp',   $heap->{remote_ip}   );
 ## $input->set('RemotePort', $heap->{remote_port} );

    #__________________________________________
    ## Server shutdown is initiated by the following:
    ##   $kernel->post( TCPServer => "shutdown" );
    ##
    ## FIX: Do we need to accomodate "shutdown" here??
    ## During shutdown POE will set a heap flag...

    ## if ($heap->{shutdown}) { ...do what?... }

    #__________________________________________
    ## FIX: currently "dispatch" is synchronous; Change this???
    ##
    $CmdClass->dispatch( $input );           # non-POE method

    return;
}

my($CR,$LF,$CRLF) = ("\015","\012","\015\012");    # socket protocol
my $GCSEOD = ":GCS_EOD:";                          # GCS protocol

sub handle_txt_output
{   my($kernel, $heap, $session, $state_args, $result_args) =
    @_[ KERNEL,  HEAP,  SESSION,  ARG0,        ARG1       ];

    # This handler is the "routeback" target that returns data
    # to client ($reply is expected to be a "$MsgClass" object).
    # Here we convert a message-based reply into a text-based 
    # reply and return it to the waiting Txt-based client.

    my $reply = $result_args->[0];
    my($stat,$err,$body) = (0,"","");

    ## warn "DEBUG: $TxtAlias: reply='$reply'\n";

    if ($reply and ref($reply) and $reply->isa($MsgClass)) {
	# warn $reply->dump();            # DEBUG

	$body        = $reply->body();
	($stat,$err) = $reply->status();
	my $tvmStatus= "GCS_Status:$stat";

	if ($err and (! $body) and ($err eq "invalid command") ) {
	    $reply = "$tvmStatus";
	} elsif ($stat) {
	    $reply = "$tvmStatus\n$err";
	} else {
	    $reply = "$tvmStatus\n$body";
	}
    }

    $reply .= "\n" unless ($reply =~ /\n$/);
    $reply .= $GCSEOD . $CRLF;                 # GCS EOD + socket protocols

   ##warn "DEBUG: $TxtAlias: (stat='$stat') body='$reply'\n";

    # The "client" attribute was added by POE to the heap to
    # facilitate sending the correct response to the correct 
    # client. All we need to do is "put" the "$reply".

    $heap->{client}->put( $reply );

    my $sessionId = $session->ID;

    $Log->write(4, "$TxtAlias: client reply sent (cid=$sessionId)");
    return;
}

sub handle_txt_connect
{   my($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

    my $sessionId = $session->ID;
    $Log->write(4, "$TxtAlias: client connect (cid=$sessionId)");

    return;
}

sub handle_txt_disconnect
{   my($kernel,$heap, $session) = @_[KERNEL,HEAP,SESSION];

    my $sessionId = $session->ID;
    $Log->write(4, "$TxtAlias: client disconnect (cid=$sessionId)");

    return;
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::TCP - Generic network TCP service

=head1 VERSION

This document describes version 0.01, released November, 2005.

=head1 SYNOPSIS

 # Startup:

 use POE::Component::GCS::Server::TCP;
 spawn POE::Component::GCS::Server::TCP;

 # Shutdown:

 $Cmd = "POE::Component::GCS::Server::Cmd";
 $Msg = "POE::Component::GCS::Server::Msg";

 $message = $Msg->new( undef, "shutdown" );
 $Cmd->dispatch( $message );

=head1 DESCRIPTION

This class implements a generic network TCP server allowing
clients to send 'command messages' to the server daemon process. 
The incoming messages from the clients are expected to be either
objects of the 'POE::Event::Message' class or subclasses thereof,
or plain text commands.

Note that a separate network port address is used for 'message
objects', and another network port is used for 'plain text'.
Be sure to send the correct message type to the correct port.

Note that 'shutdown' messages may be ignored unless they
are validated by the 'Command Dispatch' class.

=head2 Constructor

=over 4

=item spawn ( PortNumber )

This creates a TCP server session and begins listening on
the specified network B<PortNumber>.

=back

=head2 Methods

There are no other public methods defined in this class.

=head2 Events

This class has no events that are called explicitly. It
accepts client connections and adds a routing mechanism
to the header of the incoming messages to facilitate
returning output back to the client process.

All incoming messages are dispatched to the 'Command'
clas for validation and further action, if any.

=head1 DEPENDENCIES

This class expects to be run within the POE framework.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of the message protocol, see L<POE::Event::Message>.
For discussion of message extensions, see L<POE::Component::GCS::Server::Msg>.

See L<POE::Component::GCS::ClientTxt>, L<POE::Component::GCS::ClientMsg> and
L<POE::Component::GCS::Client> for examples of using message-based
 and/or text-based command messages.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
