# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Cfg.pm
# Desc:  Generic configuration module for the generic server
# Date:  Thu Sep 29 11:34:52 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::Cfg;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.09';
### @ISA     = qw( );

#------------------------------------------------------
# Note: Default settings may be overridden via an
#       external configuration file
#______________________________________________________
# Default service classes

my $CmdClass   = "POE::Component::GCS::Server::Cmd";
my $LogClass   = "POE::Component::GCS::Server::Log";
my $ProcClass  = "POE::Component::GCS::Server::Proc";
my $MsgClass   = "POE::Component::GCS::Server::Msg";
my $QueueClass = "POE::Component::GCS::Server::Queue";
my $TaskClass  = "POE::Component::GCS::Server::Task";
my $TCPClass   = "POE::Component::GCS::Server::TCP";
#______________________________________________________
# Default service settings

my $TxtPort    = 0;                       # used in TCP
my $MsgPort    = 0;                       # used in TCP
my $ThreeMins  = 60 * 3;                  # used in Task
my $ThirtySecs = 30;                      # used in Task
my $QueueIdEnv = "QUEUE_RESOURCE_ID";     # used in Proc as EV name
my $PathEnv    = "/usr/bin:/usr/local/bin:/bin"; # in Server
my $TaskFirst  = $ThirtySecs;             # used in Task
my $TaskCycle  = $ThreeMins;              # used in Task
my $LogLevel   = 3;                       # used in Log
my $ProcMax    = 5;                       # used in Queue
my $QueueMax   = 0;                       # used in Queue
my $LogFile    = "server.log";            # used in Server
my $PidFile    = "server.pid";            # used in Server
my $UidFile    = "";  ### uidgid.dat";    # used in Server
#______________________________________________________
my $CfgClient  = 0;     # skip loading server modules?

sub new
{   my($class,$cfgFile,@args) = @_;

    my $self = $Global::GLOBAL_CFGOBJ;
    return $self if $self;         # is a "singleton object"

    bless $self = {}, ref($class)||$class;
    $Global::GLOBAL_CFGOBJ = $self;

    $self->configFile( $cfgFile );
    $self->configEnv();
    $self->configLibs();
    #-------------------------------------------------------------------
    # Skip loading the server modules for clients.
    $self->loadLibs()    unless $CfgClient;
    #-------------------------------------------------------------------
    $self->configVars();

    return $self;
}

sub import
{   my($class,@args) = @_;
    $CfgClient = 1 if grep(/client/i, @args);
    return;
}

sub set    { $_[0]->{ lc $_[1]}=$_[2]     }
sub get    { return( $_[0]->{ lc $_[1]} ) }
sub param  { $_[2] ? $_[0]->{ lc $_[1]}=$_[2] : ( $_[0]->{ lc $_[1]} )    }
sub setErr { return( $_[0]->{STATUS}=$_[1]||0, $_[0]->{ERROR}=$_[2]||"" ) }
sub status { return( $_[0]->{STATUS}||0, $_[0]->{ERROR}||"" )             }
sub stat   { ( wantarray ? ($_[0]->{ERROR}||"") : ($_[0]->{STATUS} ||0) ) }
sub err    { return($_[0]->{ERROR}||"")                                   }

sub configEnv
{   my($self) = @_;

    $self->set('PathEnv', $PathEnv) unless $self->get('PathEnv');

    $ENV{PATH}   = $self->get('PathEnv');
    $ENV{PATH} ||= "/usr/local/bin /usr/bin /bin";
    $ENV{ENV}    = "";   # detaint

    return;
}

sub configLibs
{   my($self) = @_;

    $self->set('msgclass',   $MsgClass)   unless $self->get('msgclass');
    $self->set('cmdclass',   $CmdClass)   unless $self->get('cmdclass');
    $self->set('logclass',   $LogClass)   unless $self->get('logclass');
    $self->set('procclass',  $ProcClass)  unless $self->get('procclass');
    $self->set('queueclass', $QueueClass) unless $self->get('queueclass');
    $self->set('taskclass',  $TaskClass)  unless $self->get('taskclass');
    $self->set('tcpclass',   $TCPClass)   unless $self->get('tcpclass');

    return;
}

sub loadLibs
{   my($self) = @_;

    my(@libVars) = qw( msgclass   logclass  cmdclass procclass 
		       queueclass taskclass tcpclass
		   );
    foreach my $var ( @libVars ) {
	my $module = $self->get( $var );
	eval "require $module";
	$@ and die $@;
    }
    return;
}

sub configVars
{   my($self) = @_;

    $self->set('LogLevel',  $LogLevel)   unless $self->get('LogLevel'  );
    $self->set('LogFile',   $LogFile)    unless $self->get('LogFile'   );
    $self->set('PidFile',   $PidFile)    unless $self->get('PidFile'   );
    $self->set('UidFile',   $UidFile)    unless $self->get('UidFile'   );
    $self->set('TxtPort',   $TxtPort)    unless $self->get('TxtPort'   );
    $self->set('MsgPort',   $TxtPort)    unless $self->get('MsgPort'   );
    $self->set('QueueIdEnv',$QueueIdEnv) unless $self->get('QueueIdEnv');
    $self->set('ProcMax',   $ProcMax)    unless $self->get('ProcMax'   );
    $self->set('QueueMax',  $QueueMax)   unless $self->get('QueueMax'  );

    return;
}

sub configFile
{   my($self, $cfgFile) = @_;

    ## warn "DEBUG: cfgFile='$cfgFile'\n";

    $self->set('cfgFile', "");

    return unless $cfgFile;
    return unless -f $cfgFile;
    return unless -r _;

    ### warn "DEBUG: EVAL cfgFile\n";

    my $config = $self->evalConfigFile( $cfgFile );

    if ($config) {
	$self->set('cfgFile',  $cfgFile );
	my $lastUpdate = $self->statConfigFile( $cfgFile );
	$self->set('cfgFileLastUpdate',  $lastUpdate );
    } else {
	$config = {};
    }

    $self->set('msgclass',    delete $config->{MsgClass}    || $MsgClass   );
    $self->set('cmdclass',    delete $config->{CmdClass}    || $CmdClass   );
    $self->set('logclass',    delete $config->{LogClass}    || $LogClass   );
    $self->set('procclass',   delete $config->{ProcClass}   || $ProcClass  );
    $self->set('queueclass',  delete $config->{QueueClass}  || $QueueClass );
    $self->set('taskclass',   delete $config->{TaskClass}   || $TaskClass  );
    $self->set('tcpclass',    delete $config->{TCPClass}    || $TCPClass   );

    $self->set('PathEnv',     delete $config->{PathEnv}     || $PathEnv    );
    $self->set('QueueIdEnv',  delete $config->{QueueIdEnv}  || $QueueIdEnv );
    $self->set('TxtPort',     delete $config->{TxtPort}     || $TxtPort    );
    $self->set('MsgPort',     delete $config->{MsgPort}     || $MsgPort    );
    $self->set('ProcMax',     delete $config->{ProcMax}     || $ProcMax    );
    $self->set('QueueMax',    delete $config->{QueueMax}    || $QueueMax   );

    $self->set('LogFile',     delete $config->{LogFile}     || $LogFile    );
    $self->set('PidFile',     delete $config->{PidFile}     || $PidFile    );
    $self->set('UidFile',     delete $config->{UidFile}     || $UidFile    );

    # may contain a zero value. or a null value.
    #
    my $tc = delete $config->{task_cycle};

    if (defined $tc) {
        (length $tc) or ($tc = $TaskCycle);
    }
    $self->set('task_cycle', $tc); 

  # foreach my $key (sort keys %$config) {
  #	warn "Warning: invalid/unknown config parameter: $key\n";
  # }

    return $config;
}

sub evalConfigFile
{   my($self,$fileName,$reconfig) = @_;

    local(*IN);
    my $hashRef;

    $! = 0;     # reset after potential 'uidgid.dat' not found.

    if (open(IN,"<$fileName")) {
	my $data;
	while( <IN> ) {
	    last if m#^(__END__)$#;
	    $data .= $_;
	}
	$! and die "Error reading '$fileName': $!";

	close(IN);
	$! and die "Error closing '$fileName': $!";

	#FIX: get the untaint match working with \\ and \n chars.
	#$data = $self->untaint( $data, $self->dangerousChars() );
	#warn "chars='". $self->dangerousChars() ."'\n";
	#die "data='$data'\n";

	$data =~ m#(.*)#sgo; $data = $1;    # Replace this!

	# If the Perl 'eval' function fails (probably meaning
	# there's a syntax error in the config file) $hashRef 
	# will be 'undef' and '$@' will have an error string.
	#
	$hashRef = CORE::eval $data;
	my $err  = ( defined $hashRef ? undef : $@ );

	if ($err and $reconfig) {           # Do NOT abort on 'reconfig'
	    warn "Reconfig Error: $err";
	    return undef;

	} elsif ($err) {                    # DO abort on startup
	    warn "Error parsing '$fileName':\n";
	    die "Config Error: $err";
	}

      # # DEBUG:
      # foreach my $key (sort keys %$hashRef) {
      #	    warn "DEBUG: $key => $hashRef->{$key}\n";
      # }

    }
    return $hashRef;
}

#-----------------------------------------------------------------------
# Allow a few values to be reconfigured while the server is running.
# This should NOT allow changes to the server port(s) or classes used.
# Warnings are written to the log when "non-reconfig" values are seen
# to have been modified in the config file. These changes are IGNORED
# during reconfig. The daemon proc must be restarted to modify these.
# FIX: identify all "non-reconfigurable" entries in the config file.
# FIX: identify all of the classes that implement a reconfig() method.
#-----------------------------------------------------------------------

sub reconfig                  # reconfig() method not yet implemented
{   my($self) = @_;

    # First, collect changes and validate

    # ... ToDo ...


    # We can instantiate new objects here IF they are implemented
    # as singleton objects. Also, only add a reconfig() method to
    # classes where it makes sense to do so.

  # $CmdClass->new()->reconfig();        # command dispatch
  # $LogClass->new()->reconfig();        # server logging
  # $MsgClass->new()->reconfig();        # server messaging
  # $ProcClass->new()->reconfig();       # background processes
  # $QueueClass->new()->reconfig();      # queue of background tasks
  # $TaskClass->new()->reconfig();       # Task/Housekeeping class
  # $TcpClass->new()->reconfig();        # Network I/O interface

    return;
}   

sub configFileModified
{   my($self) = @_;

    my $fileName   = $self->get('cfgFile');                 # config file
    my $cachedTime = $self->get('cfgFileLastUpdate');       # last cached
    my $lastUpdate = $self->statConfigFile( $fileName );    # via stat

    return undef  unless $lastUpdate;
    return undef  unless $cachedTime;

    if ( $cachedTime < $lastUpdate ) {

	# Both set and return the new value here
	return $self->set('cfgFileLastUpdate', $lastUpdate);
    }
    return undef;
}

sub statConfigFile
{   my($self, $fileName) = @_;

    $fileName ||= $self->get('cfgFile');
    return undef  unless $fileName;
    return undef  unless -f $fileName;
    return undef  unless -r _;

    my(@stat) = CORE::stat( $fileName );        # use this in production!

    return( $stat[9] || undef );    # return mtime or undef if stat failed
}

#-----------------------------------------------------------------------
# Include this for convenience, since we're thinking about 'untainting'
# Usage:
#   $text = $CfgClass->untaint( $text [, $allowedCharList ] );
#
# Any character not in the "$allowedCharList" becomes an underscore ("_").
# The default "$allowedCharList" includes those characters identified in
# "The WWW Security FAQ" with the addition of the space (" ") character.
# An expanded set of allowed characters is available for use when the
# situation dictates. Use with care! (See also RFC1738.)

my $AllowedChars  = '- a-zA-Z0-9_.@';               # default allowed chars
my $DangerousChars= $AllowedChars .'~":;/?!@#$%^&*()+=,<>{}[]|\\'. "`'\n\t\\";

*allChars     = \&dangerousChars;
*untaintChars = \&allowedChars;
*untaintText  = \&untaintString;
*untaint      = \&untaintString;

sub allowedChars   { return $AllowedChars    }      # default allowed chars
sub dangerousChars { return $DangerousChars  }      # non-ctrl chars, tab, nl

sub untaintString
{   my($class, $text, $allowedChars) = @_;

    $allowedChars ||= $AllowedChars;                # default allowed chars

    $text =~ s/[^$allowedChars]/_/go;               # replace disallowed chars
    $text =~ m/(.*)/;                               # untaint using a match
    return $1;                                      # return untainted match
}
#-----------------------------------------------------------------------

sub dump {
    my($self)= @_;
    my($pack,$file,$line)=caller();
    my $text  = "DEBUG: ($PACK\:\:dump)\n  self='$self'\n";
       $text .= "CALLER $pack at line $line\n  ($file)\n";
    my $value;
    foreach my $param (sort keys %$self) {
	$value = $self->{$param};
	$value = $self->zeroStr( $value, "" );  # handles value of "0"
	$text .= " $param = $value\n";
    }
    $text .= "_" x 25 ."\n";
    return($text);
}

sub zeroStr
{   my($self,$value,$undef) = @_;
    return $undef unless defined $value;
    return "0"    if (length($value) and ! $value);
    return $value;
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Cfg - Generic network server config

=head1 VERSION

This document describes version 0.09, released February, 2010.

=head1 SYNOPSIS

  # Server usage - used indirecly to configure server during startup

  use POE::Component::GCS::Server;
  $configFile = "/path/to/GCS/config/file";
  exit( run POE::Component::GCS::Server( $configFile ) );

  # Client usage - used to obtain port number(s) of a running server

  use POE::Component::GCS::Server::Cfg qw( client );   # client flag

  $configClass = "POE::Component::GCS::Server::Cfg";
  $configFile  = "/path/to/GCS/config/file";
  $config   = $cfgClass->new( $cfgFile );     # will skip loadLibs()
  $msgPort  = $config->get('MsgPort');        # '0' when not in use
  $txtPort  = $config->get('TxtPort');        # '0' when not in use

=head1 DESCRIPTION

This class is used to start a generic network server daemon.
To cleanly shutdown the server, send a SIGTERM to the process ID.

Client scripts may use this module to obtain the current server 
port number(s) for running services. However, in this case, add 
the string 'client' to the 'use' statement, as shown above, to 
avoid loading all of the additional server classes.

=head2 Constructor

=over 4

=item new ( [ ConfigFile ] )

This creates a new generic server configuration object. Note
that the object created is implemented as a 'B<singleton>', 
meaning that any subsequent calls to this method will return
the original object created by the first call to this method.

The optional B<ConfigFile> parameter can be added to
specify an external file used to configure a the server. When
used, this is expected to be either a full or relative path 
to the file.

=back

=head2 Methods

=over 4

=item configEnv ( )

Configure the server Environment Variables.

=item configLibs ( )

Configure the server library modules (components).

=item loadLibs ( )

Include all of the server library modules (components). This should be
skipped when using this module in client scripts, for example to obtain 
the port number(s) of a running server. See the Synopsis section, above, 
for the correct client syntax.

=item configVars ( )

Configure defaults for server variables.

=item configFile ( [ ConfigFile ] )

Load locally customized defaults from an external data file. This is 
expected to be either a full or relative path to the file.

=back

=head2 Config File Format

The format of the external configuration file, available to allow
local customization to the server consists of a Perl 'hash' data
structure. The configurable possibilites include the following.

 # File:  conf/gcs/gcs.conf
 { 
    LogLevel    => 3,
    LogFile     => 'server.log',
    PidFile     => 'server.pid',
    UidFile     => 'uidgid.dat',

    MsgPort     => 0,
    TxtPort     => 23457,

    ProcMax     => 5,
    QueueMax    => 0,

    Uid         => 0,
    Gid         => 0,
  # Uname       => '',
  # Gname       => '',

    PathEnv     => '/bin:/sbin:/usr/bin/:/usr/sbin',
    QueueIdEnv  => 'GCS_RESOURCE_ID',
    CfgErrFatal => 'no',

    CfgClass    => "POE::Component::GCS::Server::Cfg",
    CmdClass    => "POE::Component::GCS::Server::Cmd",
    LogClass    => "POE::Component::GCS::Server::Log",
    MsgClass    => "POE::Component::GCS::Server::Msg",
    ProcClass   => "POE::Component::GCS::Server::Proc",
    QueueClass  => "POE::Component::GCS::Server::Queue",
    TaskClass   => "POE::Component::GCS::Server::Task",
    TcpClass    => "POE::Component::GCS::Server::TCP",
 }

=head3 Config File Variables

=over 4

=item LogLevel

The default logging level for the server daemon. If no entry is made
in this file, the default value is 3. This can be overridden during
debugging by starting the server with the '-D [<n>]' command-line
option. 

In addition there are three other server command-line options that
effect GCS server logging. These are handy when you temporarialy
want additional information added to the GCS server log. As this 
can get rather verbose, and is not always useful information, it
is usually best to leave the logging value set to a low number.

 -logincr           # increment current logging level
 -logdecr           # decrement current logging level
 -logreset          # reset logging level to default

Note that the minimum logging level currently available is 3.

=item LogFile

Location of the GCS server daemon's log file. 

=item PidFile

Location of the GCS server daemon's pid file. This is used for two
purposes. One, when starting a GCS server, to ensure that only one
server process runs at a time, and two, when using the GCS server
startup script to signal a running server. Use the '-h' (--help)
command-line option to see the available signal options.

=item UidFile

Location of the GCS server daemon's 'UidGid' file. This file
is optional. When used, this file will contain one line with
a numeric uid, a colon, and a numeric gid (nnnnn:nnn).

Also see the 'Uid' and 'Gid' parameters, below.

=item MsgPort

Port number on which to start a Message-based connection. All client
communication on this port is expected to be an object of the
L<POE::Event::Message> class, or a subclass thereof. 

See L<POE::Component::GCS::ClientMsg> as one example of a Message-based
client class, and see L<POE::Component::GCS::Server::Msg> as an example 
of subclassing the 'POE::Event::Message' class.

Note: One of 'MsgPort' or 'TxtPort' must be used or, when the server is
started, it will simply exit as there is no port on which to listen.

=item TxtPort

Port number on which to start a Message-based connection. All client
communication on this port is expected to be plain text. 

See 'POE::Component::GCS::ClientTxt' as one example of a Text-based
client class.

Note: One of 'TxtPort' or 'MsgPort' must be used or, when the server is
started, it will simply exit as there is no port on which to listen.

=item Uid

=item Uname

If you wish to ensure that the GCS server daemon runs as a specific
user, enter one or the other of a numeric B<Uid> or string B<Uname>
value, but not both.

These are optional. See the 'UidFile' parameter, above.

=item Gid

=item Gname

If you wish to ensure that the GCS server daemon runs as a specific
group, enter one or the other of a numeric B<Gid> or string B<Gname>
value, but not both.

=item PathEnv

It is a good idea to limit the PATH Environment Variable when starting
a daemon process. Enter a limited set of paths here. If no entry is
specified, the default is as follows.

 /bin:/sbin:/usr/bin/:/usr/sbin

=item CfgErrFatal => 'no',

It is possible to 'reconfigure' a running GCS server daemon. Edit the
server config file, then use the '-reconfig' command-line option of
the server startup command.

When using the '-reconfig' option, if errors are detected in the
config file, this flag determines what should happen. When this
flag is set to any 'true' value, reconfig errors will cause the
daemon to terminate. When this is set to any 'false' value, any
errors are ignored and the current config value(s) are retained.

=item ProcdMax

Specifies the maximum number of child processes that can run
concurrently. When tasks in the queue exceed this number, 
they will remain in the queue and, as running child procs
exit, they will be allowed to run based on the priority
value used when added to the queue.

Default value is 5.

=item QueueMax

Specifies the maximum number of tasks that can be queued. 
When additional requests to queue tasks are received, the
message for that task is set to an error status, and a
'Job queue is full' error.

Default value is 0, meaning unlimited.

=item QueueIdEnv

This one is a little esoteric. It is possible, when controlling some
limited number of child process to 'multi-process' a task, that you
will want to correlate each child process to a unique external resource.

To make this possible, an Environment Variable will be set in each
child process to a unique 'Queue Slot' value. Say for example that
the GCS server is configured to only allow 5 concurrent child
processes. Each running child will have an EV set in the range
'[0..4]' which is guaranteed to be unique for each concurrent
child process. The default value for this variable is shown here.

 GCS_RESOURCE_ID

This way, when a specific child process is a script or module that
you create, it can map this EV to the external resource that is
available for its use. Clear as mud? See a longer comment in the
source code for the 'POE::Component::GCS::Server::Proc' class.

=back

=head1 DEPENDENCIES

None currently. An external configuration file is optional.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.

For an example of client usage, see L<POE::Component::GCS::Client>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
