# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Proc.pm
# Desc:  Generic process handler service
# Date:  Wed Sep 22 14:01:28 2004
# Stat:  Prototype, Experimental
#
# Note:  Don't call "exit()" here. Excerpt from POE::Wheel::Run man page:
#        Note: Do not call exit() explicitly when executing a subroutine. 
#        POE::Wheel::Run takes special care to avoid object destructors 
#        and END blocks in the child process, and calling exit() will 
#        thwart that. You may see "POE::Kernel's run() method was never 
#        called." or worse.
#
package POE::Component::GCS::Server::Proc;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.01';
our @ISA     = qw( );

use POE qw( Wheel::Run  Filter::Reference );
use POE::Component::GCS::Server::Cfg;

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my($TaskClass, $LogClass);
my($Cfg, $Log);
my $QueueIdEnv;

#-----------------------------------------------------------------------
# Still in parent session context
#-----------------------------------------------------------------------

sub spawn
{   my($class, $task, $queueId) = @_;

    $Cfg = $CfgClass->new();
    $LogClass   = $Cfg->get('LogClass')   || die "No 'logclass' found here";
    $TaskClass  = $Cfg->get('MsgClass')   || die "No 'msgclass' found here";
    $QueueIdEnv = $Cfg->get('QueueIdEnv') || "QUEUE_RESOURCE_ID";
    $QueueIdEnv = $class->untaint( $QueueIdEnv );     # NO Surprises Needed!

    # Note: The events generated here are handled in the Control session, 
    # and that's where the handler methods are defined. This provides the 
    # communication path from child to parent.

    $Log = $LogClass->new();
    $Log and $Log->write(5, "spawning a process (qid=$queueId)");

    my $wheel = POE::Wheel::Run->new
    (   Program      => sub { $class->startTask( $task, $queueId ) },
        StdoutFilter => POE::Filter::Reference->new(),
     ## StderrFilter => POE::Filter::Reference->new(), ### No STDERR filter!
        StdoutEvent  => "wheel_stdout",    # Note: event renamed in Control.
        StderrEvent  => "wheel_stderr",    # Note: event renamed in Control.
        CloseEvent   => "wheel_done",      # Generate here! Not in Control!
	ErrorEvent   => "wheel_ERROR",
    );

    return $wheel;        # return wheel so Controller can track everything
}

#-----------------------------------------------------------------------
# Now entering child process
#-----------------------------------------------------------------------

# WARNING: DO NOT "print", "write" or otherwise leak output to STDOUT
# below this line!! It will NOT do what you expect. The child's stdout
# is filtered and anything unexpected causes BIG debugging problems.
# The symptom is that output never gets back to the control session.
#
# If you want output back to the parent's STDOUT, write to STDERR here!
# The parent prepends a timestamp and "TASK(n): " to every stderr line.

sub startTask
{   my($class,$task,$queueId) = @_;

    my $response = $TaskClass->new( $task );
 ## $response->header->set('tvm_taskPid', $$);
 ## $response->header->set('tvm_queueId', $queueId);

    # For convenience of client scripts. See Queue class for details.
    $ENV{$QueueIdEnv} = $queueId;

    my $command = $task->body();

    # Perform substitution for symbolic reference to "$queueId"
    $command =~ s/%qid%/$queueId/i;

    my($result, $stat, $shellStatus) = $class->runCmd( $command );

    if ($stat) {
	$response->header->setErr($stat,$result);
    } else {
	$response->header->setErr(0,"");
	$response->body( $result );
    }

    $class->out2parent( $response );

    ## Two ways of sending text to the controlling session's STDOUT
    ## warn "JUST TESTING";
    ## $class->err2parent( "JUST TESTING" );

    return;
}

sub runCmd
{   my($class,$cmd,@args) = @_;

    $cmd = $class->untaint( $cmd );   # we SHOULD be running with -T switch

    # Run a command using Perl's "open()" via the pipe ("|") character.
    # Note: It's not appropriate in this script to simply run a child
    # using Perl's `backtick` operator. Here we must explicitly open
    # the system command pipe and test for multiple failure modes.

    my($result,$stat,$sig,$shellStatus) = ("",0,0,"0");
    local(*CMD);

    #-------------------------------------------------------------------
    # HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT HINT
    # How to add a custom command to be run as a child process.
    # o  first, add a new 'valid command' definition
    #    (see the HINT section in the 'PoCo::GCS::Cmd' class)
    # o  here, '$cmd' will contain your newly valid command
    #    so just test for the value and invoke a handler of
    #    your choice: run a script, invoke a method on a module
    #    or whatever.
    #
    # Warning: Here you must, MUST use the '$Log->warn()' method. 
    # DO NOT "print", "write" or otherwise leak anything to STDOUT.
    # This child's stdout is filtered using POE::Filter::Reference,
    # and any non-object stdout entry causes BIG debugging problems.
    # The symptom is that a result never gets back from this child.

    if ($cmd =~ /^myCmd/) {

        $Log and $Log->warn(
	    3, "Okay: process '$cmd' (not really, it's a demo)"
	);

    sleep 10;   # DEBUG ... to test queue limits, queue full.

	# For example, run a script:
        #    $cmd = "/my/command/script";    # just fall through to exec()
        #
	# or return result of a module call:
	#    return($result,$stat) = MyModule->cmdMethod( $cmd );
        #
	# ... or whatever.
    }

    # Note: since an *asynchronous* response is expected here
    # (which is why you would want to run something here),
    # an immediate reply has already been sent back to the 
    # waiting client--then, after the child process completes,
    # an additional message (email, msg object, or whatever) 
    # can be sent to indicate result of the child process.
    # Just send the reply address as an argument to the command
    # message that ends up here and route any result to that event.
    #-------------------------------------------------------------------

  ## $class->err2parent( "Sleeping for 10..." );       # TEST/DEBUG
  ## sleep 10;

    # FIX: allow redirection into a log file
    #      for both OUT and ERR (separately??)

  ## Use this format of the "exec" to pass STDERR directly to parent
  ## if (! (my $chpid = open(CMD, "exec $cmd @args |")) ) {

  ## Use this format of the "exec" to capture STDERR output here
  ##
  # if (! (my $chpid = open(CMD, "exec $cmd @args 2>&1 |")) ) {

    if (! (my $chpid = open(CMD, "exec $cmd       2>&1 |")) ) {
        ($stat,$result) = (-1, "fork failed: $!");

	### $class->err2parent("=" x 20 ."ERROR: $result");

    } else {
        my(@result) = <CMD>;             # ensure the pipe is emptied here
        $result = (@result ? join("",@result) : "");
        chomp($result);

        if (! close(CMD) ) {
            if ($!) {
                $stat = -1;
                $result and $result .= "\n";
                $result .= "Error: command close() failed: $!";

		# $class->err2parent("=" x 20 ."ERROR: $result");
		$class->err2parent("DEBUG: path='$ENV{PATH}' in '$PACK'");
            }
            if ($?) {
                ($stat,$sig,$shellStatus) = $class->rcAnalysis( $? );
            }
        }
    }

    ###$class->err2parent("=" x 20 ." STAT='$shellStatus' result='$result'");

    return( $result, $stat, $shellStatus, $!, $? );
}

sub rcAnalysis
{   my($class,$rc) = @_;
    #
    # Modified somewhat from the example in "Programming Perl", 2ed.,
    # by Larry Wall, et. al, Chap 3, pg. 230 ("system" function call)
    # This now works on HP-UX systems (thanks to Doug Robinson ;-)
    # Returned "$stat" will mimic what the various shells are doing.
    #
    my($stat,$sig,$shellStatus);          # $shellStatus used in log files.

    $rc = $? unless (defined $rc);

    $rc &= 0xffff;

    if ($rc == 0) {
        ($stat,$sig,$shellStatus) = (0,0,"0");
    } elsif ($rc & 0xff) {
        $rc &= 0xff;
        ($stat,$sig,$shellStatus) = ($rc,$rc,"signal $rc");
        if ($rc & 0x80) {
            $rc &= ~0x80;
            $sig = $rc;
            $shellStatus = "signal $sig (core dumped)";
        }
    } else {
       $rc >>= 8;
       ($stat,$sig,$shellStatus) = ($rc,0,$rc); # no signal, just exit status
    }
  # 0 and print "DEBUG: rcAnalysis is returning ($stat,$sig,$shellStatus)\n";
    # Note: $shellStatus is the closest value as the Shell's $?
    return($stat,$sig,$shellStatus);
}

# Usage:
#   $text = $class->untaint( $text [, $allowedCharList ] );
#
# Any character not in the "$allowedCharList" becomes an underscore ("_")
# The default "$allowedCharList" includes those characters identified in
# "The WWW Security FAQ" with the addition of the space (" ") character.

sub untaint
{   my($class, $text, $allowedChars) = @_;

    $allowedChars ||= '- a-zA-Z0-9_.@';      # default allowed chars

    $text =~ s/[^$allowedChars]/_/go;        # replace disallowed chars
    $text =~ m/(.*)/;                        # untaint using a match
    return $1;                               # return untainted match
}

sub out2parent
{   my($class,$message) = @_;

    ## warn "DEBUG: out2parent: message='$message'\n";

    return unless $message and ref($message);
    $message->send( *STDOUT );
}

#------------------------------------------------------
# Note: STDERR is NOT currently filtered for messages;
# this allows any child errors easily back to parent.
#------------------------------------------------------

sub err2parent
{   my($class,$text) = @_;
    return unless $text;
    print STDERR $text;
    print STDERR "\n" unless $text =~ m#\n$#;

### $message->send( *STDERR );
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Proc - Generic process handler service

=head1 VERSION

This document describes version 0.01, released November, 2005.

=head1 SYNOPSIS

 use POE::Component::GCS::Server::Proc;

 $ProcClass = "POE::Component::GCS::Server::Proc";

 $ProcClas->spawn( Task, QueueId );

 $wheel = $Log = "POE::Component::GCS::Server::Log";

 my $wheelId  = $wheel->ID();
 my $wheelPid = $wheel->PID();

 $heap->{wid} = $wheelId;
 $heap->{pid} = $wheelPid;


=head1 DESCRIPTION

=head2 Constructor

=over 4

=item spawn ( Task, QueueId )

The B<spawn> method is used to start a child process.

=over 4

=item Task

The B<Task> is expected to be an object of the
'POE::Event::Message' class or a subclass thereof.

=item QueueId

This parameter is expected to be a unique identifier
for each task that runs concurrently. It is used to
map a task to an arbitrary external resource.

=back

=back

=head2 Methods

There are no public methods defined in this class.

=head1 DEPENDENCIES

This class is expected to be run within the context of
a POE 'Session.'

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of server configuration, see L<POE::Component::GCS::Server::Cfg>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
