# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Task.pm
# Desc:  Generic event-driven task service
# Date:  Wed Oct 12 11:29:38 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::Task;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.05';
#our @ISA    = qw( );

use POE qw( Session );
use POE::Component::GCS::Server::Cfg;
use POE::Component::GCS::Server::Cmd;

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my $CmdClass = "POE::Component::GCS::Server::Cmd";
my($LogClass, $MsgClass);
my($Cfg, $Log, $Debug);

my($TaskFirst, $TaskCycle);    # FIX this... no longer a 'TaskFirst' setting
my $ClientId = "Task";


sub new { bless {}, ref($_[0])||$_[0]  }

sub whichMsgClass { $MsgClass };

sub spawn
{   my($self,@args) = @_;

    ref $self or $self = $self->new();

    $Cfg = $CfgClass->new();
    $LogClass  = $Cfg->get('LogClass')   || die "No 'logclass' found here";
    $MsgClass  = $Cfg->get('MsgClass')   || die "No 'msgclass' found here";
  # $TaskFirst = $Cfg->get('task_first') || die "No 'task_first' found here";
    $Debug     = $Cfg->get('debugObj')   || die "No 'debugobj' found here";

  # $TaskCycle = $Cfg->get('task_cycle');   # may contain a zero
  # length $TaskCycle or die "No 'task_cycle' found here";

    $Log = $LogClass->new();
    $Log and $Log->write(0, "spawning $ClientId service");

    $MsgClass = $self->whichMsgClass() ||$MsgClass;

    POE::Session->create( 
	object_states => [ $self => $self->getObjectStates() ],
    );

    return;
}

sub getObjectStates
{   my($self) = @_;

    return {
	      _start => '_start',
       routine_tasks => 'handle_routine_tasks',

             respond => 'handle_send_response',
               reply => 'handle_send_response',

       caught_signal => 'handle_signals',
           set_timer => 'handle_set_delay',
               delay => 'handle_set_delay',

    #-------------------------------------------------------------------
    # TEST/DEBUG stuff 
   
             bounce_to => 'handle_message_bounce_to',
           bounce_from => 'handle_message_bounce_from',
    };
}

sub _start
{   my($self, $kernel) = @_[ OBJECT, KERNEL ];

    # Allow other sessions to post events to us:
    $kernel->alias_set("task");

    $Log and $Log->write(7, "starting Task service");

    $self->config( "init" );             # allows for init and reconfig

    $self->initSignals();                # set up signal handlers

    # Start timer delay for routine housekeeping tasks
    #
 #  my($event, $secsDelay, $arg) = ("routine_tasks", $TaskFirst, "");
 #  $self->setTimer( $event, $secsDelay, $arg );

    return;
}

#-----------------------------------------------------------------------
# Allow for both config at startup and reconfig during run-time
# DO NOT abort during reconfig. Simply report any invalid settings.

*config = \&reconfig;

sub reconfig
{   my($self,$mode) = @_;

    $mode ||= "";

    # Only write this message during reconfig, not during init
    #
    $Log->write(5, "Performing reconfig in '$PACK'")
	unless ($mode and $mode eq "init");

    # ... add reconfig steps here ...

    return;
}
#-----------------------------------------------------------------------

sub handle_routine_tasks
{   my($self, $kernel, @args) = @_[ OBJECT, KERNEL, ARG0..$#_ ];

    $Log and $Log->write(9, "Task: timer POP: handle routine task (args='@args')");

    # Just before exiting, set timer for next wakeup call
    #
    return unless $TaskCycle;        # may be "turned off" via config file

    $self->setTimer( "routine_tasks", $TaskCycle, "" );
    return;
}

sub handle_send_response
{   my($self, $stateArgs, $routeArgs) = @_[ OBJECT, ARG0, ARG1 ];

    my $message = $routeArgs->[0];

    ##warn "DEBUG: Task 'reply': stateArgs='@{ $stateArgs }'\n";
    ##warn "DEBUG: Task 'reply': routeArgs='@{ $routeArgs }'\n";

    return unless ($message and ref($message) and $message->isa( $MsgClass ));

    my $response = $MsgClass->new( $message, "" );

    $Log->write(9, "Task: sending response from task");

    $response->route();
    return;
}

#-----------------------------------------------------------------------
# Signal Handling ... POE events, not OS/Perl signals
#-----------------------------------------------------------------------

# Name       Value  Operation performed         Keyboard   cmd switch
# ---------  -----  --------------------------  ---------  ----------
# SIGHUP  -    1    reread configuration file              -reconfig
# SIGINT  -    2    reset log level to default  (Ctrl+C)   -logreset
# SIGQUIT -    3    start "graceful" shutdown   (Ctrl+\)   -quit
# SIGKILL -    9    kill the server daemon                 -kill
# SIGPIPE -   13    do a "hard" shutdown                   -stop
# SIGTERM -   15    start "graceful" shutdown              -shutdown
# SIGUSR1 -   16    increases log level by 2               -logincr
# SIGUSR2 -   17    decreases log level by 2               -logdecr
# SIGCONT -   18    resume suspended process    ('fg' cmd) -cont
# SIGSTOP -   19    suspend server process      (Ctrl+z)   -stop

sub initSignals
{   my($self) = @_;

    $Log->write(9, "$ClientId: Initialize signal handlers");

    POE::Kernel->sig( "HUP",  "caught_signal" );   # ( 1)  Reread Config File
    POE::Kernel->sig( "INT",  "caught_signal" );   # ( 2)  Reset Log Level
    POE::Kernel->sig( "QUIT", "caught_signal" );   # ( 3)  Graceful Shutdown
    POE::Kernel->sig( "PIPE", "caught_signal" );   # (13)  Hard Shutdown
    POE::Kernel->sig( "TERM", "caught_signal" );   # (15)  Graceful Shutdown
    POE::Kernel->sig( "USR1", "caught_signal" );   # (16)  incr Log Level
    POE::Kernel->sig( "USR2", "caught_signal" );   # (17)  decr Log Level

    return;
}

sub handle_signals
{   my($self, $kernel, $sig) = @_[ OBJECT, KERNEL, ARG0 ];

    # Note: this is a POE event and NOT a "real" Perl signal
    # handling subroutine. As such, it's okay to create new
    # variables here.
    
    my $logLevel;
    my $minLogLevel = 3;

    $Log->write(0, "-" x 50 );

    if ( $sig eq "INT" ) {                         # -logreset (RESET)
        $logLevel = $Log->setLogLevel ( $minLogLevel );

        $Log->write(0, "$ClientId: Received SIG$sig (LogLevel=$logLevel)");
        $Log->write(0, " (Use 'Ctl+\\' to shutdown server)")
            if $Debug->isSet();

    } elsif ( $sig eq "USR1" ) {                   # -logincr  (ADD 2)
        $logLevel = $Log->incrLogLevel( 2 );

        $Log->write(0, "$ClientId: Received SIG$sig (LogLevel=$logLevel)");

    } elsif ( $sig eq "USR2" ) {                   # -logdecr  (SUB 2)
        # Update if possible, but do not drop below minimum log level!

        $logLevel = $Log->getLogLevel();
        $logLevel = $Log->decrLogLevel( 2 )  if ($logLevel > $minLogLevel);

        $Log->write(0, "$ClientId: Received SIG$sig (LogLevel=$logLevel)");

    } elsif ( $sig =~ /^(HUP|QUIT|PIPE|TERM)$/ ) {
        $Log->write(0, "$ClientId: Received SIG$sig");

    } else {
        $Log->write(0, "$ClientId: Received SIG$sig (IGNORED)");
    }

    $Log->write(0, "-" x 50 );

    #----------------------------------------------------
    # Here we initiate server reconfiguration. Note that only
    # some of the configurable values are "reconfigurable".
    #
    # WARN: Don't confuse the call here to "reconfigureServer()"
    # with the "reconfig()" method near the top of this class.
    # The former initiates Server reconfiguration while the latter
    # is called by the Config class to reconfigure this module.

    if ($sig eq "HUP") {                           # -reconfig
        $self->reconfigureServer( undef );

    #----------------------------------------------------
    # Here we initiate a "graceful" shutdown: This command
    # should ONLY work when it comes from our "$ClientId".
    #
    } elsif ( $sig =~ /^(TERM|QUIT)$/ ) {          # -shutdown -quit Ctrl-\

        my $request = $MsgClass->new( undef, "shutdown");
        $request->setClientId( $ClientId );

        $CmdClass->dispatch( $request );

    #----------------------------------------------------
    # Hard shutdown. Use this as a next-to-last resort.
    # The final resort is to use the "-kill" cmd-line 
    # option ('kill -9') which can't be trapped here.
    #
    } elsif ($sig eq "PIPE") {                     # -stop

        # Just before shutdown, dump pool data and counters.
        #
        $self->writeStatsToLog();

        $Log->write(0, "$ClientId: Hard Abort: Server terminating.");
        exit(0);
    }

    $kernel->sig_handled;
    return;
}

#-----------------------------------------------------------------------
# Server Reconfiguration
#-----------------------------------------------------------------------

sub reconfigureServer
{   my($self, $autoFlag) = @_;


    $Log->write(0, "$ClientId: Warning: server reconfig not yet implemented.");
    return;


    # WARN: Don't confuse the "reconfigureServer()" method here with
    # the "reconfig()" method at the top of the Housekeeping class.
    # THIS method initiates general Server reconfiguration, while
    # THAT method is called by the Config class to reconfigure
    # this particular GCS module. (Reminds me of the famous old
    # "twisty maze of little passages, all different.")

    if ( ! $Cfg->configFileModified() ) {
        # Skip this log entry if called from normal Housekeep cycle.
        # It only needs to be seen when "manually" requested via the
        # "client -reconfig" command.

        return if ($autoFlag);      # called via Hk cycle: Skip log entry

        $Log->write(0, "$ClientId: Config file update time has not changed.");
        return;                     # no change to cfg file: Skip reconfig
    }

    $Log->write(0, "$ClientId: Config file update time has changed.");
    $Log->write(0, "$ClientId: Starting server reconfig.");

    $Cfg->reconfig();               # FIX: implement reconfig() method in Cfg

    ## warn $Cfg->dump();

    $Log->write(0, "$ClientId: Server reconfig complete.");
    return;
}

#-----------------------------------------------------------------------
# Timers and Delays
# Note: A timer can be set either through an event (here) or
# through a regular non-POE method call (below).
#-----------------------------------------------------------------------

sub handle_set_delay
{   my($self, $stateArgs,$routeArgs) = @_[ OBJECT, ARG0, ARG1 ];

    $stateArgs ||= [];
    $routeArgs ||= [];

    my $event = shift @$stateArgs ||"";
    my $delay = shift @$stateArgs ||"";

    $self->setDelay( $event, $delay, $stateArgs, $routeArgs );
    return;
}

sub handle_del_delay
{   my($self, $stateArgs, $routeArgs) = @_[ OBJECT, ARG0, ARG1 ];

    my $alarmId = $stateArgs->[0];

    $self->delDelay( $alarmId );
    return;
}

#-----------------------------------------------------------------------
# Simple object methods: these are not POE event handlers
#-----------------------------------------------------------------------

sub setDelay
{   my($self, $event, $delay, $stateArgs, $routeArgs) = @_;

    return unless $event;
    return unless defined $delay;
    return if     $delay =~ /\D/;

    $Log->write(9,"Task: setDelay: call '$event' in $delay secs");

    # Set a delay for the named $event. This will cause both the
    # "$stateArgs" and "$routeArgs" list refs to be passed to 
    # that event after the given delay.

    my $alarmId =
	$poe_kernel->delay_set( $event, $delay, $stateArgs, $routeArgs );

    if (! $alarmId ) {
	warn "ERROR: error in 'setTimer' method of '$PACK': $!\n";
    }
    return $alarmId;
}

sub delDelay
{   my($self, $alarmId) = @_;

    return undef unless $alarmId;

    $Log->write(9,"Task: delDelay: remove alarm '$alarmId'");

    my $alarmRef = $poe_kernel->alarm_remove( $alarmId );

    if (! $alarmRef ) {
	warn "ERROR: error in 'delTimer' method of '$PACK': $!\n";
    }
    return $alarmRef;
}

#-----------------------------------------------------------------------
# TESTING / DEBUGGING  --  Experiment with message interception/routing
#-----------------------------------------------------------------------

sub handle_message_bounce_to                     # via POST/CALL
{   my($self, $session,  $stateArgs, $routeArgs) =
    @_[ OBJECT, SESSION,  ARG0,       ARG1 ];
    
    my $message = $routeArgs->[0];    # 0th element in "ARG1" list ref

    return unless ($message and ref($message));

    # See the "_bounce" and "_bounceEcho" methods in Command class
    # for examples of generating events that invoke this method.
    #
    # This is a "post/call" target for testing message interception.
    # It reroutes message to the 'handle_message_bounce_from' method
    # which then returns message to the original destination. This
    # is "plug-compatible" with the existing POE "post/call" feature.
    #
    # Note that, after the "route()" is called below, the receiving
    # event handler will find any "@stateArgs" in the "ARG0" ref, and
    # "$message" as the FIRST argument in the "ARG1" list ref, just
    # as when using "postbacks". Any additional args that are added
    # during the "route()" call will follow in the "ARG1" list ref.
    #
    # A log entry is created AFTER the "route()" to demonstrate the
    # difference between using "post" (async) vs. "call" (sync).
    # .  when using "call" the "bounce_from" entry is logged first
    # .  when using "post" the "bounce_to"   entry is logged first

  # my $toSession = "";               # allow default to current context
    my $event     = "bounce_from";    # 2nd redirect for this message
    my(@stateArgs)= ();               # sent to "ARG0" in target event
    my(@routeArgs)= ();               # added to "ARG1" in target event

  # $message->addRouteBack( "call", "",       $event, @stateArgs );  # SYNC
    $message->addRouteBack( "post", $session, $event, @stateArgs );  # ASYNC

    $message->route( @routeArgs );    # forward message to next event

    $Log->write(3, "$ClientId: DEBUG: msg bounced in 'bounce_to' event");

    return 0;     # indicate success, when 'call' used instead of 'post'
}

sub handle_message_bounce_from                   # via POSTBACK/CALLBACK
{   my($self, $session,  $stateArgs, $routeArgs) =
    @_[ OBJECT, SESSION,  ARG0,       ARG1 ];

    # This is "postback"/"routeback" target for testing message bounce
    # It is invoked simply by adding a routeBack to a message, as shown
    # above. And here the message is merely forwarded on. Any source
    # or destination method will not know of the interception. This
    # is "plug-compatible" with POE's "postback/callback" feature.

    my $message = $routeArgs->[0];    # 0th element in "ARG1" list ref

    return unless ($message and ref($message));

    $message->route();                # forward message to next event

    $Log->write(3, "$ClientId: DEBUG: msg bounced in 'bounce_from' event");

    return 0;     # success, when 'callback' used instead of 'postback'
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Task - Generic event-driven task service

=head1 VERSION

This document describes version 0.05, released March, 2006.

=head1 SYNOPSIS

  use POE::Component::GCS::Server::Task;
  spawn POE::Component::GCS::Server::Task;


=head1 DESCRIPTION

This class is used to create a POE session that manages short
term tasks. A timer can be used to initiate routine ongoing
types of tasks.

=head2 Constructor

=over 4

=item spawn ( )

This creates a new generic POE 'Session' that can be used
to run routine tasks on an ongoing basis.

=back


=head2 Methods

=over 4

=item getObjectStates

=item _start

=item setTimer

=back


=head2 Events

=over 4

=item handle_routine_tasks

=item handle_set_delay

=item handle_send_response

=back


=head1 DEPENDENCIES

This class expects to run within the POE framework.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of the message protocol, see L<POE::Event::Message>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
