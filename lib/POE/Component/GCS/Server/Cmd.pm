# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Cmd.pm
# Desc:  Generic command validation and dispatch
# Date:  Thu Sep 29 11:48:32 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::Cmd;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.12';
our @ISA     = qw( );

use POE;                                            # Use POE!
use POE::Component::GCS::Server::Cfg;               # configuration class
use PTools::String;                                 # for 'plural()' method

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my($LogClass, $MsgClass, $TaskClass, $TcpClass);
my($CtlClass);
my($Cfg, $Log);
my $DebugMode;
##($CacheClass, $Cache);

#-----------------------------------------------------------------------
# Table driven command dispatch allows for scalability

sub METHOD { 0 }           # "Constant" indices into "$cmd_lookup" table
sub USER   { 1 }
sub MODE   { 2 }
sub RESP   { 3 }

# User validation values 
my $ANY_USER    = "";       # Empty string
my $TASK_SERVICE= "Task";   # Task service  # make configurable??

# Mode validation values
my $ANY_MODE    = "";       # Empty string
my $DEBUG_MODE  = "D";      # Debug mode only, set via "spawn" method

my $RESPOND     = 1;        # This class responds to the request
my $NO_RESPONSE = 0;        # Another service responds to request

my $cmd_defaults = {
    # Generic commands used to test various components
    banner  => [ _banner => $ANY_USER, $ANY_MODE, $NO_RESPONSE ],
    echo    => [ _echo   => $ANY_USER, $ANY_MODE, $NO_RESPONSE ],
    help    => [ _help   => $ANY_USER, $ANY_MODE, $RESPOND     ],
    ping    => [ _ping   => $ANY_USER, $ANY_MODE, $RESPOND     ],
    sleep   => [ _sleep  => $ANY_USER, $ANY_MODE, $NO_RESPONSE ],

    #-------------------------------------------------------------------
    # HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT 
    # The 3 steps to implementing a new command in the GCS server.
    #
    # o  Step 1: add a new entry to '$cmd_defaults' hash reference:

    myCmd   => [ _myCmd  => $ANY_USER, $ANY_MODE, $RESPOND ],

    # o  Step 2: add a new 'command dispatch' method in this class
    #    (see the  'sub _myCmd' definition, below)
    #
    # o  Step 3: add a new 'command handler' to start a child process
    #    (see HINT section in the PoCo::GCS::Proc class)
    #
    # Notes:
    # o  use "$RESPOND" here, as an immediate response is generated
    #    in this class. Then, when the task is completed, some sort
    #    of other response (email, whatever) can be sent directly
    #    from the child process to the user/admin/whatever
    #
    # o  also, you might want to add a 'help_lookup' entry, below.
    #-------------------------------------------------------------------

    # WARN: Debug commands are available to ANY user, service, etc.,
    # but ONLY when a non-zero "$debug" flag is passed to 'spawn'
    # (as when the "-D" (-Debug) option is used to start the server).
    #
    dump       => [ "_dump",       $ANY_USER, $DEBUG_MODE, $RESPOND     ],
    bounce     => [ "_bounce",     $ANY_USER, $DEBUG_MODE, $NO_RESPONSE ],
    bounceEcho => [ "_bounceEcho", $ANY_USER, $DEBUG_MODE, $NO_RESPONSE ],

    # System commands are available to internal service(s) ONLY 
    # (this is true whether the "$debug" flag is set or not).
    shutdown => [ "_shutdown", $TASK_SERVICE, $ANY_MODE, $NO_RESPONSE ],
    startup  => [ "_startup",  $TASK_SERVICE, $ANY_MODE, $NO_RESPONSE ],
};

my $help_lookup = {
    #-------------------------------------------------------------------------
    # Synopsis of 'client' commands supported by the GCS Server
    #-------------------------------------------------------------------------
    banner   =>
    "banner <text>                       # test Ctrl/Maint service    (user) ",

    bounce   =>
    "bounce                              # bounce a message around    (debug)",

    bounceEcho =>
    "bounceEcho <text>                   # bounce an echo msg around  (debug)",

    dump     =>
    "dump [<item(s)>]                    # dump various items to log  (debug)",

    echo     =>
    "echo <text>                         # test Ctrl/Maint service    (user) ",

    help     =>
    "help                                # display this help message  (user) ",

    ping     =>
    "ping                                # test the Command service   (user) ",

    sleep    =>
    "sleep <secs>                        # test Housekeeping service  (user) ",

};

#-----------------------------------------------------------------------

sub spawn
{   my($class, $debugObj, $cmd_lookup) = @_;

    $DebugMode    = ( $debugObj->isSet() ? "D" : "" );
    $cmd_defaults = $cmd_lookup if ($cmd_lookup and ref($cmd_lookup));

    $Cfg = $CfgClass->new();
  # $CacheClass = $Cfg->get('CacheClass') || die "No 'cacheclass' found here";
    $CtlClass   = $Cfg->get('QueueClass') || die "No 'queueclass' found here";
    $LogClass   = $Cfg->get('LogClass')   || die "No 'logclass' found here";
    $MsgClass   = $Cfg->get('MsgClass')   || die "No 'msgclass' found here";
    $TaskClass  = $Cfg->get('TaskClass')  || die "No 'taskclass' found here";
    $TcpClass   = $Cfg->get('TcpClass')   || die "No 'tcpclass' found here";

  # $Cache = $CacheClass->new();    # not yet used here.
    $Log   = $LogClass->new() || die "Can't create new $LogClass";

    ## warn "DEBUG: MsgClass='$MsgClass'";
    ## warn "DEBUG:    Debug='$DebugMode'";

    return;
}

sub dispatch
{   my($class, $message, $cmd_lookup) = @_;

    #-------------------------------------------------------------------
    # FIRSTLY: Is this a valid message object?
    #
    if (! ($message and ref($message) and $message->isa($MsgClass)) ) {
	$Log->write(2, "Cmd: error: $message (not a '$MsgClass')");
	$class->_invalid_request( $message );
	return;
    }
    $cmd_lookup ||= $cmd_defaults;

    my $command    = $message->body();
    my $clientId   = $message->get('ClientId')   ||"";
    my $remoteHost = $message->get('RemoteHost') ||"";

    ### The folowing log entry may be helpful for debugging, 
    ### but don't use it in production. Full command strings
    ### may have embedded "keywords" that should't be logged.
    ###
    ### $Log->write(2, "Cmd: dispatch(cid=$clientId): $command");

    my($lookup_value) = $command =~ m#^\s*(\S*)#;
    my $lookup_ref = $cmd_lookup->{ $lookup_value };

    $Log->write(2, "Cmd: dispatch(cid=$clientId): $lookup_value");
    #-------------------------------------------------------------------
    # SECONDLY: Is this a valid request?
    #
    my($method, $valid_user, $valid_mode, $send_response);
    if ($lookup_ref) {
	($method, $valid_user, $valid_mode, $send_response) = @{ $lookup_ref };
    } else {
	($method, $valid_user, $valid_mode, $send_response) = ("","","","");
    }

    # The folowing log entry may be helpful for debugging, 
    # but DO NOT use it in production. Full command strings
    # may have embedded "keywords" that should not be logged.
    # $method and 
    ## $Log->write(9, "Cmd: dispatch(cid=$clientId): call '$method' for '$command'");

    #-------------------------------------------------------------------
    # THIRDLY: Is request in a valid context?
    #
    if ($valid_user and ! $valid_user =~ /^$clientId$/) {
	$class->_invalid_request( $message );
	return;

    } elsif ($valid_mode and ! $valid_mode =~ /^$DebugMode$/) {
	$class->_invalid_request( $message );
	return;
    }

    #-------------------------------------------------------------------
    # FOURTHLY: dispatch the command!
    #
    my $response;

    if ($method and $class->can( $method )) {

	$response = $class->$method( $message ) ||"";

	# Helpful for debugging(?), but not for production:
	# $Log->write(7, "Cmd: response(cid=$clientId): response '$response' from '$method'");

    } else {
	$class->_invalid_request( $message );
	return;
    }

    #-------------------------------------------------------------------
    # PENULTIMATELY: log the result
    #
    if ($response) {
	if (! (ref($response) and $response->isa($MsgClass)) ) {
	    $class->invalid_response( $response );
	    return;
	}

	## $msg_body  = $response->body() ||"";
	## $log_level = ( $response->status() ? 2 : 9 );

	# Be more verbose if error. either way don't log "body" here.

	if ($response->status() ) {
	    my $err = $response->err();
	    $Log->write( 2, "Cmd: result(cid=$clientId): error: '$err'" );
	} else {
	    $Log->write( 9, "Cmd: result(cid=$clientId): successful" );
	}
    }

    #-------------------------------------------------------------------
    # FINALLY: send a response
    #
    if ($response and $send_response) {
	$response->route();

     #	if ($response->stat()) {
     #	    my $err = $response->err();
     #	    $Log->write(2, "Cmd: dispatch(cid=$clientId): Error: $err");
     #	}
    }

    return;
}

#-----------------------------------------------------------------------
#   Command dispatch methods
#-----------------------------------------------------------------------

sub _ping
{   my($class, $message) = @_;
    return $MsgClass->new( $message, "pong" );
}

sub _sleep
{   my($class, $message) = @_;

    # Just a hand-off here: the "delay" event will eventually 
    # pass the incoming $message to the "reply" event, also in
    # the Task service. After the delay, that service will invoke 
    # any routeback that was placed in the "$message->header()" 
    # by the TCP service.

    my $command    = $message->body();
    my($delay)     = $command =~ m#(\d*)$#;
    my $service    = "task";
    my $event      = "delay";
    my(@stateArgs) = ( reply => $delay );
    my(@routeArgs) = ();

    ## my $status = $poe_kernel->post( @service, @params );
    ## warn "DEBUG: poe_kernel->post( @service, @params ): ($status, $!)";

    $message->addRouteTo( "post", $service, $event, @stateArgs );
    $message->route( @routeArgs );

    return undef;
}

*_banner = \&_echo;            # banner and echo can use the same method

sub _echo
{   my($class, $message) = @_;

    # Simply generate an "add_entry" event for the Control session.
    # The routeback for this command is called in the Control class.

    my $queuePri = undef;
    $message->addRouteTo( "post", "process_queue", "add_entry", $queuePri );
    $message->route();

    return undef;
}

sub _myCmd
{   my($class, $message) = @_;

    # HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT 
    # This is Step 2 of three steps in implementing a new command.
    #
    # A couple of tricky things to note here are:
    # -  use 'call' when we 'add_entry' to the queue so we
    #    get any 'Job queue is full' error immediately
    #
    # -  if we get an error, create an error response for the client
    #    otherwise, create a success response for the client (which
    #    is now waiting at the other end of the TCP connection).

    #-------------------------------------------------------------------
    # First, write a log entry of what we're about to do.

    my $clientId = $message->get('ClientId')   ||"";                  # DEBUG
    my $command  = $message->body();                                  # DEBUG
    $Log->write(3, "Cmd: send to queue(cid=$clientId): '$command'");  # DEBUG

    #-------------------------------------------------------------------
    # Next, send the incoming command '$message' off to the queue.
    # Use 'call' routing here so we get an IMMEDIATE status result.

    my $queuePri = undef;
    $message->addRouteTo( "call", "process_queue", "add_entry", $queuePri );

    my($stat,$err) = $message->route();

    #-------------------------------------------------------------------
    # Next, create and send an immediate result back to the waiting 
    # client. That's all we need to do here.

    my $response;

    if ($stat) {
	$response = $MsgClass->new( $message, "" );
	$err ||= "Unable to queue request: see server log for details";
	$response->setErr( $stat, $err );
    } else {
	my $success_result = "Okay: your request has been queued";
	$response = $MsgClass->new( $message, $success_result );
    }
    return $response;

    # Then, Step 3 in the PoCo::GCS::Proc class, is to process the 
    # command and send some sort of results/status notification message 
    # to the user/admin/whoever. (See HINT section in that class for 
    # a continuation of this command example.)
}

sub _help 
{   my($class, $message) = @_; 

    # This will return "server command" help, which is quite
    # useful when testing/debugging (dunno about you, but I
    # tend to forget the syntax for seldom used commands ;-)
    # So, "<clientCmd>" now has three levels of help available:
    # Usage:
    #        <clientCmd> -h        # standard user help text
    #        <clientCmd> -hD       # incl "standard" test cmds
    #        <clientCmd> help      # GCS server command help
    #
    # This will also omit "debug" commands from the help
    # listing when not currently in "$DebugMode".

    my $help_text;
    $help_text .= "-" x 72 ."\n";
    $help_text .= "Synopsis of 'client' commands supported by the GCS Server\n";
    $help_text .= "-" x 72 ."\n";

    foreach my $key (sort keys %$help_lookup) {
        ## my $text = $help_lookup->{$key};
        ## next if ( ($text =~ /debug/i) and (! $DebugMode) );
    
        if ( (defined $cmd_defaults->{$key})
        and  ($cmd_defaults->{$key}->[MODE] eq $DEBUG_MODE)
        and  (! $DebugMode) ) {
            next;
        }
        my $text = $help_lookup->{$key};
        $help_text .= "$text\n";
    }
    $help_text .= "-" x 72 ."\n";

    my $response = $MsgClass->new( $message, $help_text );

    return $response;
}
#-----------------------------------------------------------------------
# The following asynchronous methods are restricted to the Housekeeping
# service ONLY. See dispatch table, above, for the allow/deny mechanism.
#-----------------------------------------------------------------------

sub _startup
{   my($class, $message) = @_;

    # This is the 'TCP' server startup message, delayed during
    # system initialization. A '=== GCS System Startup ==='
    # message has already been logged via the 'Cfg' class.  # FIX: which class?

    $Log->write(1, "--------------- TCP Server Startup ---------------");
    
    return $TcpClass->spawn();
}

sub _shutdown
{   my($class, $message) = @_;

    my $command  = $message->body();
    my $clientId = $message->get('ClientId')  ||"";

    if ($clientId ne $TASK_SERVICE) {
        my $response   = $MsgClass->new( $message, "unknown command" );
    
        $Log->write(1, "Cmd: dispatch(cid=$clientId): ($command) IGNORE: incorrect 'cid'"); 
    
        return $class->_invalid_request( $response );
    }

    $Log->write(7, "Cmd: dispatch ($command): STOP GCS SERVER");
    $Log->write(1, "--------------- TCP Server Shutdown --------------");

    # Stop listening for new GCS client connections:
    # Note that both or only one of the two TCP servers may have
    # been started. Here we don't care either way. Just send the
    # shutdown command. If the server(s) weren't started, then the
    # event(s) will be silently ignored by the POE kernel.
    #
    POE::Kernel->call( TxtServer => "shutdown" );
    POE::Kernel->call( MsgServer => "shutdown" );

    # FIX: if any tasks are running, wait for them before exit!
    #
    $Log->write(1, "Cmd: checking for running background jobs ...");

    my $taskCount = $CtlClass->taskCount();
   
    if ( $taskCount ) {    # FIX: how to handle waiting for running jobs??
        my $jobs = PTools::String->plural( $taskCount, "job", "s are", " is" );
   
        $Log->write(0, "Cmd: $taskCount maintenance $jobs running...");
        $Log->write(0, "Cmd: Warning: GCS server exiting prior to completion.");
   
    } else {
        $Log->write(0, "Cmd: no background jobs are currently running");
    }

    # Are there any other issues/tasks that need to be completed here?
    # If so, then add them here.

    $Log->write(1, "=============== GCS System Shutdown ==============");

    ## die PTools::Local->dump('inclib');     # DEBUG

    exit(0);          # no return as script exits here
}

#-----------------------------------------------------------------------
#   Experimental methods - fun with message routing
#-----------------------------------------------------------------------

sub _bounce
{   my($class, $message) = @_;

    my $response = $MsgClass->new( $message, "follow the bouncing ball" );

    $Log->write(7, "Cmd: dispatch (bounce): Route to TASK Class");
    #
    # Experiment with the temporary re-routing of messages
    #
    $response->addRouteTo("post", "task", "bounce_to");
    $response->route();

    return $response;       # be consistent, even if no response here.
}

sub _bounceEcho
{   my($class, $message) = @_;

    my $command  = $message->body();
       $command =~ s/^bounceEcho/echo/;
    my $response = $MsgClass->new( $message, $command );
    my $queuePri = undef;

    $Log->write(7, "Cmd: dispatch (bounceEcho): Route to QUEUE, etc.");
    #
    # Here's one usage scenario:
    # Add a temporary return routing of the message... but
    # first, route this message to the "echo" processor...
    # (routing directives are pushed on a LIFO queue).
    #
    # Note that the "bounce_to" event will add further
    # routing before the message eventually returns to
    # the TCP interface and, finally, back to the client.
    # Tail the log file to follow the bouncing message.
    # Using "call", the routing upon exiting the queue,
    # will be a synchronous call to the "bounce_to" event.

    $response->addRouteTo("call", "task", "bounce_to");
    $response->addRouteTo("post", "queue", "add_entry", $queuePri );

    # Here's another usage scenario:
    # First, route this message to the "echo" processor...
    # and add a temporary return routing of the message.
    #
    # (Since these are both LIFO queues, any routing that
    # is currently contained in this message [such as the
    # "routeBack" added by the TCP interface] will work
    # as intended and neither TCP nor Queue will have any
    # knowledge that the message was intercepted, either
    # along the way in or along the way back out.)
    #
 ## $response->addRouteTo("post", "queue", "add_entry", $queuePri );
 ## $response->addRouteBack("post", "task", "bounce_from");

    # In addition, the "interceptor" methods along the way
    # won't need to know anything about the original source
    # or the destination of the message. Eventually, the
    # Message class will be extended to route between various
    # POE-based servers on this same or other host machine(s)
    # using the same routing mechanism. In this way we can
    # accomplish "sequential broadcasting" (or perhaps a
    # better term will be "routecasting").
    #
    # Note that while either of the two scenarios above
    # work nicely as a demo, combining them both (as they
    # are currently defined) will not give good results.

    $response->route();

    return $response;       # be consistent, even if no response here.
}

sub _dump
{   my($class, $message) = @_;

    #-------------------------------------------------------------------
    # Dump various debug info to the system log file. Valid arguments
    # include any supported by the "dump()" method on the PerlTools
    # "PTools::Local" class. This module is loaded by the 
    # "POE::Component::GCS::Server" class and, if that should change, 
    # then this command will stop working.
    #
    # Usage:
    #   <clientCmd> dump             - log "vars" by default (is verbose)
    #   <clientCmd> dump env         - log current Environment Variables
    #   <clientCmd> dump inclib      - log full paths of included modules
    #   <clientCmd> dump incpath     - log current library include path(s)
    #   <clientCmd> dump origpath    - log the original lib include path(s)
    #   <clientCmd> dump vars        - log all local/global attrs and values
    #   <clientCmd> dump all         - log all of the above
    #   <clientCmd> dump env,inclib  - combinations are okay, too
    #
    # In addition, the current configuration values can be dumped to
    # the server log. This invokes the "dump()" method on the Config
    # class.
    #
    # Usage:
    #   <clientCmd> dump config
    #
    #-------------------------------------------------------------------

    my $command  = $message->body();
    my($args)    = ($command =~ /^dump\s*(.*)/);
    my $response = $MsgClass->new( $message );

    if ($args =~ /config/) {
        warn $Cfg->dump();
        $response->body( "dumped 'config args' to server log" );
        return $response;
    }

    if ( defined $INC{'PTools/Local.pm'} ) {
        $args ||= "vars";               # default for "PTools::Local->dump()"
        warn PTools::Local->dump( $args );
        $response->body( "dumped '$args' to server log" );

    } else {
        $response->setErr( -1, "sorry, but 'PTools::Local' was not used" );
    }

    return $response;
}

#-----------------------------------------------------------------------
#   Error handling methods
#-----------------------------------------------------------------------

sub _invalid_response
{   my($class, $message, $error_text) = @_;

    $error_text ||= "internal error: invalid response; see server log.";

    $class->_invalid_request( $message, $error_text );
    return;
}

sub _invalid_request
{   my($class, $message, $error_text) = @_;

    $error_text ||= "invalid command";

    # We must reply with SOMETHING or TCP clients will hang. Simply
    # closing the socket results in a "no response from server" error.

    my $command  = $message->body();
    my $clientId = $message->get('ClientId') ||"";

    my $response = $MsgClass->new( $message, $command );
    $response->setErr( -1, $error_text );
  # $response->body( $command );

    $Log->write(2, "Cmd: dispatch(cid=$clientId): error is '$error_text'");

    $response->route();
    return;
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Cmd - Generic command validation and dispatch

=head1 VERSION

This document describes version 0.12, released March, 2006.

=head1 SYNOPSIS

Create a subclass to extend the B<Command Set> used to dispatch commands.

  package My::Network::Server;
  use vars qw( @ISA );
  @ISA = qw( POE::Component::GCS::Server::Cmd );

  use POE::Component::GCS::Server::Cmd;
  use POE::Event::Message;

  sub spawn
  {   my($class, $debug_flag, $command_set) = @_;

      $debug_flag ||= 0;

      $ANY_USER   = q{};      # Empty string
      $ANY_MODE   = q{};      # Empty string
      $DEBUG_MODE = q{D};     # Letter "D"
      $RESPOND    = 1;        # This class responds to the request
      $NO_RESPONSE= 0;        # Another service responds to request

      $command_set ||= {
	  # Generic commands that are dispatched by this class:
	  ping    => [ _ping   => $ANY_USER, $ANY_MODE,   $RESPOND     ],
	  sleep   => [ _sleep  => $ANY_USER, $ANY_MODE,   $NO_RESPONSE ],
	  echo    => [ _echo   => $ANY_USER, $ANY_MODE,   $NO_RESPONSE ],
	  banner  => [ _banner => $ANY_USER, $ANY_MODE,   $NO_RESPONSE ],

	  # Additional commands require methods defined in a subclass:
	  dump    => [ _dump   => $ANY_USER, $DEBUG_MODE, $RESPOND     ],
      };

      POE::Component::GCS::Server::Cmd->spawn( $debug_flag, $command_set );
  }

  sub _dump
  {   my($class, $message) = @_;

      my $response = POE::Event::Message->new( 
	  $message, 
	  "The 'dump' method is not yet implemented." 
      );

      return $response;
  }

Then, after 'spawning' the Command dispatch service, other services
can make use of this service as shown here. This minimal example
does not show the POE Session contect that is assumed to exist here.

  use POE::Component::GCS::Server::Cmd;
  use POE::Event::Message;

  $Cmd = "POE::Component::GCS::Server::Cmd";

  $message = POE::Event::Message->new( undef, "ping" );

  $method = "post";         # "post," to enqueue a POE event, or
                            # "call," for immediate response

  $service = "";            # "" for Current Session, or name of session

  $event   = "event_name";  # Name of event in the session that will
			    # accept the response.

  @state_args = ();         # State args, as with a POE 'postback'

  $message->addRouteBack( $method, $service, $event, @state_args );

  $Cmd->dispatch( $message );

To successfully 'catch' the response, a method handler for the 
named B<$event> must exist in the B<current session> (or, if a
named B<$service> was given, in the B<named session>). Any
B<@state_args> are used in a similar manner to POE's B<postback>
mechanism.


=head1 DESCRIPTION

This class is used to validate and dispatch commands within a generic 
network server daemon. Method lookup and partial command validation 
are performed via a table driven B<command set>. This is used to 
minimize performance penalties as the command set grows in a subclass.

To cleanly subclass, simply extend the B<command set>, as described below,
and define the additional dispatch handler methods in the derived class.

If the generic commands and methods remain included in the "command set", 
as shown in the Synopsis, above, this class will attempt to dispatch
these as well. The success of this operation will depend on whether the
services they requre exist in a network server derived from this set
of 'B<PoCo-GCS>' base classes.

Note that this module is not event driven. The assumptions are that

=over 4

=item *

a command will be dispatched from within some event handler

=item *

for some commnds it may be appropriate to return immediate results

=item *

command dispatch should be quick and efficient, and 

=item *

for some commands, an event may be generated by the dispatcher and
there should not be a 'double dispatch' penalty for using this class

=back

As such, this generic class is implemented to dispatch commands
synchronously. This allows for immediate dispatch where appropriate,
and avoids generating two events for a single command.


=head2 Constructor

=over 4

=item spawn ( [ Debug ] [, CommandSet ] )

This creates a new generic server configuration object. Note
that the object created is implemented as a 'B<singleton>', 
meaning that any subsequent calls to this method will return
the original object created by the first call to this method.

An optional B<Debug> parameter can be added to enable additional
commands that are only valid during debugging and testing. This
parameter can be any non-zero value.

An optional B<CommandSet> can, and should,  be passed to extend 
the limited set of 'demo' commands provided with this base class.
This parameter should be a data structure with similar format
as the one provided with this class.

=back

=head2 Methods

=over 4

=item dispatch ( Message )

This method validates and dispatches command messages.

=over 4

=item Message

The required B<Message> argument is expected to be an object
or subclass of the 'POE::Event::Message' class.

Replies to messages should be constructed as shown here. This
syntax allows the '$response' to include the unique 'message ID'
(from the original '$message' header) as an 'In Reply To' header
in the '$response'. Useful for situations where an event needs
to correlate various messages and responses.

 $response = $message->new( $message, "body of response" );

 $response->route();

=back

=back

=head1 DEPENDENCIES

None currently.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of the message protocol, see L<POE::Event::Message>.

For notes on adding additional commands to the GCS server, see
two 'HINT' sections in the source code for this class and 
one 'HINT' section in the source for the L<POE::Component::Server::Proc>
class.

=head1 AUTHOR

Chris Cobb, E<lt>no spam please at ccobb dot netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
