# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Queue.pm
# Desc:  Generic queue service for "controlled process parallelism"
# Date:  Tue Oct 11 10:22:41 2005
# Stat:  Prototype, Experimental
#
# Service Alias:  queue
# Public Events:  add_queue ( $task, $priority )
#
# Usage:
#        $poe_kernel->post( queue => "add_queue", $message, 5 );
#
# Note:  The "$message" (task to run) is expected to be a subclass
#        of the "POE::Event::Message" class, and to have one or more
#        "routeto"/"routeback" header(s) allowing for "auto-reply."
#
package POE::Component::GCS::Server::Queue;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.05';
#our @ISA    = qw( );

use POE qw( Session  Filter::Reference  Queue::Array );
use POE::Component::GCS::Server::Cfg;

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my($LogClass, $ProcClass);
my($Cfg, $Log);

my($ProcMax,$QueueMax);
my $TasksRunning = 0;
my $TasksQueued  = 0;
my $QueueSlots;

#________________________________________________________________
# Note: Here the "$QueueClass" is the data structure used by this class 
# to implement the process queue. This queue is NOT configurable via
# settings in the "Cfg class." However, THIS module IS set via config 
# so, if you don't like this implementation, feel free to replace it.

my $QueueClass = "POE::Queue::Array";
my($Queue);
#________________________________________________________________
# Here it's possible to define a 'queue is full' condition.
# Some experimenting may be necessary to determine a good value.

sub new { bless {}, ref($_[0])||$_[0] }

sub MAX_CONCURRENT { $ProcMax ||5  }
sub TASKS_RUNNING  { $TasksRunning }
sub TASKS_QUEUED   { $TasksQueued  }
sub tasksRunning   { $TasksRunning }
sub tasksQueued    { $TasksQueued  }
sub queueIsFull    { ($QueueMax) and (TASKS_QUEUED >= $QueueMax) }
### queueIsFull    { return( 0 )   }    # Disable 'Job queue is full' errors

*taskCount = \&tasksRunning;

sub spawn
{   my($class,$maxConcurrent) = @_;

    my $self = new $class;

    $Cfg = $CfgClass->new();
    $LogClass  = $Cfg->get('LogClass')  || die "No 'logclass' found here";
    $ProcClass = $Cfg->get('ProcClass') || die "No 'procclass' found here";
    $ProcMax   = $Cfg->get('ProcMax')   || 5;
    $QueueMax  = $Cfg->get('QueueMax')  || 0;

    $Log = $LogClass->new;
    $Log and $Log->write(0, "spawning Queue service");

    # Create the Controller session that throttles concurrent tasks.
    # Here we define SOME of the "POE events" that we will service.
    # Other events for parent/child communication are defined below.

    $Global::GLOBAL_QUEUE_MAX = $maxConcurrent ||3;
    $QueueSlots = $self->initQueueSlots( MAX_CONCURRENT );

    POE::Session->create
    ( object_states =>
	[ $self => {
	      _start => '_start_controller',
	 start_tasks => 'start_tasks',
	   next_task => 'start_tasks',

	# PUBLIC EVENTS:
	   add_entry => 'handle_add_queue',      # add a task to the queue
	   add_queue => 'handle_add_queue',      # add a task to the queue
	     enqueue => 'handle_add_queue',      # add a task to the queue

    #	task_timeout => 'handle_task_timeout',
    #	task_cleanup => 'handle_task_cleanup',
    #	    all_done => 'handle_all_done',
    #  caught_signal => 'handle_signals',
	            }
	],

	## heap => { },                # Note: $self is used insted of "heap" 
    );
    return;
}

sub _start_controller
{   my($self, $kernel) = @_[ OBJECT, KERNEL ];

    # Allow other sessions to post events to us:
    $kernel->alias_set("queue");
    $kernel->alias_set("process_queue");         # 2nd alias doesn't work??

    $Log and $Log->write(7, "Queue: initializing process controller queue" );

    $Queue = $QueueClass->new();

 ## # Set up signal handlers to allow clean interrupts
 ## # print "    configuring signal watcher ...\n";
 ## $kernel->sig( "HUP",  "caught_signal" );
 ## $kernel->sig( "INT",  "caught_signal" );
 ## $kernel->sig( "TERM", "caught_signal" );

    $kernel->sig( "CHLD", "child_exited"  );  # caught but ignored, for now...

  ### Added a sigCHLD event...even though we ignore it for now,  ###
  ### it's presence will cause POE to reap child procs as they   ###
  ### terminate. Can this still cause 'unhandled' child deaths   ###
  ### which show up after this Driver class is done processing?? ###
  ### FIX: set up a CHLD signal handler such that this Driver    ###
  ### session will not quit until the last child proc is reaped. ###

    $kernel->yield( "start_tasks" );
    return;
}

sub start_tasks
{   my($self, $kernel, $session) = @_[ OBJECT, KERNEL, SESSION ];

    while ( $TasksRunning < MAX_CONCURRENT ) {

	my($pri,$id,$task) = $Queue->dequeue_next();

	last unless ( $task );

	$TasksQueued--;

	my $cmd = $task->body();
	$Log and $Log->write(5, "Queue: dequeue task='$task'" );

	$self->run_wheel( $task );
    }
    return;
}

sub handle_add_queue
{   my($self, $kernel, $argRef0, $argRef1) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];

    my $pri  = $argRef0->[0]   || 5;
    my $task = $argRef1->[0]   || return;
    my $cid  = $task->header->get('ClientId');    # client TCP sessID

    if ( $self->queueIsFull() ) {
	return unless ref( $task );

        my $err = "Cannot queue task: job queue is full";
	$task->setErr(-1,$err);
	$task->route();

	$Log and $Log->write(1, "Queue: Error: QUEUE IS FULL (Max=$ProcMax)(cid=$cid)" );

	return( -1, $err );
    }
    $Log and $Log->write(7, "Queue: OKAY: ADDED TO QUEUE (cid=$cid)" );

    $Queue->enqueue( $pri, $task );

    $TasksQueued++;

    $kernel->yield("next_task");
    return( 0, "" );
}

#-----------------------------------------------------------------------
#   Individual Wheel methods
#-----------------------------------------------------------------------

sub run_wheel                  # NOTE: Method not called by POE here.
{   my($self, $task) = @_;

    # Here we define the handlers for events generated by the
    # child co-process as configured in the "Proc" class.
    # There is one session created for each wheel that is run
    # which simplifies collecting the results from the wheel.

    my $qid = $self->mapTask2QueueSlot( $task );

    $Log and $Log->write(5, "Queue: starting task process (qid=$qid)" );

    POE::Session->create
    ( object_states =>
	[ $self => {
	      _start => '_start_wheel',
	wheel_stdout => 'handle_task_stdout',    # a child's stdout (Wheel)
	wheel_stderr => 'handle_task_stderr',    # a child's stderr (Wheel)
	  wheel_done => 'handle_task_done',      # a child is done  (Wheel)
       	 wheel_ERROR => 'handle_task_ERROR',     # a child's ERROR  (Wheel)
	            }
	],
	args => [ $task, $qid ],      # passed to "_start" ('_start_wheel')
	## heap => {},                # default "heap" is "{}"
    );

    return;
}

sub _start_wheel
{   my($heap, $session, $task,$queueId) = @_[ HEAP, SESSION, ARG0..ARG1 ];

    #---------------------------------------------------------------
    # FINALLY. Here's where we actually start a wheel (co-process).
    #
    my $wheel = $ProcClass->spawn( $task, $queueId );

    if (! $wheel) {
	$task->setErr(-1,"Unable to create child process for task");

	$task->route();
	return;
    }

    my $wheelId  = $wheel->ID();
    my $wheelPid = $wheel->PID();

    # Note: this syntax ASSUMES current session only controls ONE wheel!
    #
    $heap->{wheel} = $wheel;           # MUST cache to keep session "alive"
    $heap->{pid}   = $wheelPid;        # child process ID  - for convenience
    $heap->{qid}   = $queueId;         # queue resource ID - for convenience
    $heap->{wid}   = $wheelId;         # wheel's uneque ID - for convenience
    $heap->{cid}   = $task->header->get('ClientId');    # client TCP sessID
    $heap->{task}  = $task;
    #---------------------------------------------------------------

    $TasksRunning++;
    if ($heap->{cid}) {
	$Log and $Log->write(5, "Queue: TASK($wheelId): RUN (cid=$heap->{cid})(pid=$wheelPid)(qid=$queueId)(running tasks: $TasksRunning)" );
    } else {
	$Log and $Log->write(5, "Queue: TASK($wheelId): RUN (pid=$wheelPid)(qid=$queueId)(running tasks: $TasksRunning)" );
    }

    return;
}

sub handle_task_stdout
{   my($heap, $kernel, $message, $wheelId) = @_[ HEAP, KERNEL, ARG0..ARG1 ];

  # die "Logic Error: wheelId='$wheelId' (expecting wheelId='$heap->{wid})"
  #	unless $wheelId == $heap->{wid};

 ## $message ||="";
 ## warn "DEBUG: message='$message'  wheelId='$wheelId'\n";

    my $taskPid = $message->header->get('tvm_taskPid') ||0;

    $Log and $Log->write(10, "Queue: TASK($wheelId): OUT received: $message" );

    ## warn $message->dump();

    $message->route();

    my $origTask = delete $heap->{task};             # output was returned
    return;
}

sub handle_task_stderr
{   my($heap, $kernel, $message, $wheelId) = @_[ HEAP, KERNEL, ARG0..ARG1 ];

  # die "Logic Error: wheelId=$wheelId (expecting wheelId=$heap->{wid})"
  #	unless $wheelId == $heap->{wid};

    $Log and $Log->write( 3, "Queue: TASK($wheelId): $message" );
    return;
}

sub handle_task_done
{   my($self, $heap, $kernel, $wheelId ) = @_[ OBJECT, HEAP, KERNEL, ARG0 ];

  # die "Logic Error: wheelId='$wheelId' (expecting wheelId='$heap->{wid})"
  #	unless $wheelId == $heap->{wid};

    delete $heap->{wheel};             # MUST uncache to allow POE's cleanup!
    delete $heap->{wid};

    my $pid = delete $heap->{pid};
    my $qid = delete $heap->{qid};
    my $cid = delete $heap->{cid};

    $self->delTask4QueueSlot( $qid );

    $TasksRunning--;
    if ($cid) {
	$Log and $Log->write(5, "Queue: TASK($wheelId): END (cid=$cid)(pid=$pid)(qid=$qid)(running tasks: $TasksRunning)" );
    } else {
	$Log and $Log->write(5, "Queue: TASK($wheelId): END (pid=$pid)(qid=$qid)(running tasks: $TasksRunning)" );
    }

    # If we still have the 'origTask' in the heap, it means
    # that the expected return from 'handle_task_stdout' did
    # not complete successfully. Return something here.
    #
    my $origTask = delete $heap->{task};                # output NOT returned

    if ($origTask) {
	$origTask->setErr(-1,"No output from child process");

	$origTask->route();
    }

    $kernel->post("queue", "next_task");     # yield to "next_task"
    return;
}

sub handle_task_ERROR
{   my($self, $kernel, @args) = @_[ HEAP, KERNEL, ARG0..$#_ ];

    return unless $args[1];  # no errro? no message.
    warn "OUCH: enter 'handle_task_ERROR'...\n";

    print "=" x 45 ."\n";
    print "OUCH: ERROR syscall='$args[0]'\n";
    print "OUCH: ERROR   errno='$args[1]'\n";
    print "OUCH: ERROR   error='$args[2]'\n";
    print "OUCH: ERROR wheelId='$args[3]'\n";
    print "OUCH: ERROR  handle='$args[4]'\n";
    print "=" x 45 ."\n";
    return;
}

#-----------------------------------------------------------------------
#   Map $task to $wheel - unused/unneeded
#-----------------------------------------------------------------------

## Usage:  $self->mapWheel2Task( $wheelId, $task );
##         $task = $self->delTask4Wheel( $wheelId );
##
#my $TaskList = {}
#
#sub mapWheel2Task { $TaskList->{ $_[1] } = $_[2] }
#sub delTask4Wheel { delete $TaskList->{ $_[1] }  }

#-----------------------------------------------------------------------
#   QueueID    (a.k.a.: "QID" and "Queue Slot Mechanism")
#-----------------------------------------------------------------------
# This is a funky little thing and it has nothing to do with actual
# "slots" in POE's queue architecture. This is just a way to provide 
# a link (or mapping) from a conceptual "slot" within this module, 
# to some external script or process that might make use of it.
#
# It is VERY useful for tasks that require a 1-to-1 relationship
# between each task in a number of concurrent "tasks" running and 
# an arbitrary external resource used while the tasks are running.
#
# Will an example help? For instance, counting every element in 
# a ClearCase VOB requires running one single "cleartool find" 
# command in one single ClearCase View. Trying to "multi task"
# finds within one View fails due to limitations within a View. 
# Given a case where there are 170+ ClearCase VOBs, it would be
# VERY nice to run multiple "find" commands at a time, each one
# running in a UNIQUE View, until all 170 or so finds complete.
#
# However, how do you ensure that ONLY ONE "find" command runs
# within a particular View at any given time? Voila! You can use
# the "queue slot" number to map a given task to a given View.
#
#    Parent      "Task"       User         Mapped
#    Process     Process     Process      to a View
#   =========    ========   =========     ----------
#    ________     ______     _______       ________
#   |        |   |      |   | queue |     |        |
#   | Queue  |---| Proc |---| slot1 | --> | View 1 |
#   |________|\  |______|   |_______|     |________|
#              \  ______     _______       ________
#               \|      |   | queue |     |        |
#                | Proc |---| slotN | --> | View N |
#                |______|   |_______|     |________|
#
# So, how does a User Process make use of this feature? Either by
# embedding the symbolic construct  %qid%  within the arguments 
# to a given command, or by accessing the environment variable 
#  QUEUE_RESOURCE_ID  which gets set to current QueueID value.
# Note: the name of this environment variable is configurable 
# via the "POE::Component::GCS::Server::Cfg" class, using the
# 'QueueIdEnv' variable name.
#
# If this is still not clear, feel free to ignore this feature.
# But DON'T break it. Some processes will rely on this for sure.
#

my $FmtString = "%3.3d";

sub initQueueSlots
{   my($self,$max_concurrent) = @_;
    my $digits = length( $max_concurrent );
    $digits = 3 if ($digits < 3);
    $FmtString = "%". $digits .".". $digits ."d";
    return [];
}

sub mapTask2QueueSlot
{   my($self,$task) = @_;

    # Find the next available queue "slot" within
    # the CURRENT value for MAX_CONCURRENT

    my($idx,$fts) = (0,0);
    foreach $idx (0 .. MAX_CONCURRENT - 1) {
        $fts = $idx;  ## sprintf( $FmtString, $idx );
        last if ! defined $QueueSlots->[ $idx ];
    }
    die "Logic Error: no available ResID locations"
        if (defined $QueueSlots->[ $fts ]);

    die "Logic Error: available ResID locations exceeded"
        if ($fts > MAX_CONCURRENT);

    $QueueSlots->[ $fts ] = $task;

    return sprintf( $FmtString, $fts );
}

sub delTask4QueueSlot
{   my($self,$qid) = @_;
    $QueueSlots->[ $qid ] = undef;
}
#_________________________
1; # Required by require()


__END__

=head1 NAME

POE::Component::GCS::Server::Queue - Generic queue service

=head1 VERSION

This document describes version 0.04, released March, 2006.

=head1 SYNOPSIS

  use POE::Component::GCS::Server::Queue;
  spawn POE::Component::GCS::Server::Queue;

  $poe_kernel->post( "queue", $message, $priority );
  

=head1 DESCRIPTION

This class provides a generic process queuing service. This allows
"controlled process parallelism" within the Generic Server.

=head2 Constructor

=over 4

=item spawn ( [ MaxConcurrent ] )

This creates a new generic queue manager object. Note
that the object created is implemented as a 'B<singleton>', 
meaning that any subsequent calls to this method will return
the original object created by the first call to this method.

The optional B<MaxConcurrent> parameter can be added to
specify the maximum number of concurrent child processes
that are allowed to run at any given time. This value
defaults to B<3>.

=back

=head2 Methods

There are no public methods other than those described above.

=head2 Events

=over 4

=item ( queue, Message, Priority )

This POE event allows queing tasks to run with the certainty
that only a limited number of tasks will run concurrently.

 $poe_kernel->post( queue => $message, $messagePriority );

=over 4

=item queue

This is the name of the event to queue the given task.

=item Message

The required B<Message> argument is expected to be an object
or subclass of the 'POE::Event::Message' class. 

As input, the message is expected to contain a command recognized 
by the 'POE::Component::GCS::Server::Proc' class, or a subclass
thereof.

For output, the results from running the command are included as 
the body of the reply. The message is expected to contain one
or more predefined routing header(s). 

=back

=back

=head1 DEPENDENCIES

This class is expected to be run with the POE framework.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of the message protocol, see L<POE::Event::Message>.

For implementation of the message protocol in the GCS server, 
see L<POE::Component::GCS::Server::Msg>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
