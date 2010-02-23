# -*- Perl -*-
#
# File:  POE/Component/GCS/Server.pm
# Desc:  GCS: Generic client/server model
# Date:  Thu Sep 29 11:48:32 2005
# Stat:  Prototype, Experimental
#
# Synopsis:
#     #!/opt/perl/bin/perl -T
#     use POE::Component::GCS::Server;
#     $configFile = "";    # optional
#     exit( run POE::Component::GCS::Server( $configFile ) );
#
# See documentation located after the __END__ of this module for
# additional Synopsis, Description, Usage, etc.
#

package POE::Component::GCS::Server;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.03';
our @ISA     = qw( );                 # Defines interitance relationships

use POE;                              # Use POE!
use POE::Component::GCS::Server::Cfg; # Server configuration class
use PTools::Local;                    # Local/Global var environment
use POSIX qw( errno_h );              # Defines CORE::kill errors
use PTools::Proc::Daemonize;          # Turn script into a daemon process
use PTools::Options;                  # Cmd-line options parser
use PTools::Debug;                    # Debug-level output
use PTools::Verbose;                  # Verbose-level output

my $Local    = "PTools::Local";
my $PathEnv  = "/usr/bin:/usr/sbin";
my($BaseName)= ( $0 =~ m#^(?:.*/)?(.*)# );
my $DefaultConfigFile = $Local->path('app_cfgdir', "gcs/gcs.conf");
my($Opts,$Debug,$Verbose);

my $CfgClass = "POE::Component::GCS::Server::Cfg";
my($CmdService, $LogService, $QueueService, $TaskService, $TCPService);
my($Cfg, $Log);


sub run
{   my($class,$cfgFile,$uid,$gid,$umask) = @_;

    $ENV{PATH} = $PathEnv;                 # hopefully we're running with "-T"

    $Opts = $class->parseCmdLine();        # parse/validate cmd-line opts/args

    $Cfg = $class->getConfig( $cfgFile );  # parse/validate server config file

    $class->daemonize($uid,$gid,$umask);   # turn script into a daemon process

    $class->initialize();                  # init and startup various services

    $poe_kernel->run();                    # finally, we start the POE kernel

    return 0;                              # return status to OS
}

sub import
{   my($class,$cfgFile,@args) = @_;
    return unless $cfgFile;
    $Cfg = new POE::Component::GCS::Server::Cfg( $cfgFile, @args );
    return;
}

#sub opts    { $Opts            }
#sub debug   { $Opts->debug()   }
#sub verbose { $Opts->verbose() }

sub initialize
{   my($class) = @_;     ### ,$cfgFile,@args) = @_;

    ###### Too late here ### $Cfg = $CfgClass->new( $cfgFile, @args );

    $Cfg->set('debugObj',   $Debug);    # --- Are these too much of a hack??
    $Cfg->set('verboseObj', $Verbose);  # --- 

    $CmdService   = $Cfg->get('CmdClass')   || die "No 'cmdclass' found here";
    $LogService   = $Cfg->get('LogClass')   || die "No 'logclass' found here";
    $QueueService = $Cfg->get('QueueClass') || die "No 'queueclass' found here";
    $TaskService  = $Cfg->get('TaskClass')  || die "No 'taskclass' found here";
    $TCPService   = $Cfg->get('TCPClass')   || die "No 'tcpclass' found here";

    #---------------------------------------------
    # Must wait to do this step after loading the config file.
    # Implement "-l <n>" ("-logLevel <n>") in conjunction
    # with a possible 'config.dat' file entry and also a
    # possible "-D <n>" ("-Debug <n>") cmd-line switch.
    # Presidence ordering is as follows.
    #  low  - default value of 3
    #   .   - config.dat value
    #   .   - "-l <n>" (-logLevel <n>) entered on cmd-line
    #  high - "debug level" if greater than any of the above
    # HOWEVER, if a "-l <n>" value is passed, RETAIN this as
    # the default logging level to use with "-logreset".
    # FIX: enable log level retention in the 'Task' class.

    my($logLevel, $dbgLevel);
    $logLevel = $Opts->get('logLevel') || $Cfg->get('logLevel') || 3;
    $Cfg->set('logLevel', $logLevel);

    $dbgLevel = $Debug->getLevel();
    $logLevel = $dbgLevel  if ( $dbgLevel > $logLevel );

    $Log = $LogService->spawn( $logLevel );
    #---------------------------------------------

    $Log->write(0, "=============== GCS System Startup ===============");

    $CmdService->spawn( $Debug );
    $QueueService->spawn();
    $TaskService->spawn();
    $TCPService->spawn();

    # FIX? Create a separate TCP server startup event to run
    # after all other initialization have signaled "complete."
    # This way we ensure any/all connection attempts succeed.

    return;
}

#-----------------------------------------------------------------------
# Convert script into a background daemon process
#-----------------------------------------------------------------------

sub daemonize
{   my($class,$uid,$gid,$umask) = @_;

    # Turn the current process into a background daemon process,
    # including verify user configuration and untaint PATH, EVs,
    # redirecting standard IO, and detaching the session from any
    # controlling terminal. Note that both 'IO redirection' and
    # 'session detach' are skipped when Debug flag is non-zero.
    # See PTools::Proc::Daemonize man page for all of the details.
    #
    # NOTE that when a debug-level is set (script run with "-D [n]")
    # 'IO redirection' and 'session detach' are SKIPPED, meaning
    # that the process stays in the foreground and STDOUT/STDERR
    # appear in the terminal window instead of going to a log file.

    my $logFile = $Cfg->get('LogFile') || die "No 'logfile' found here";
    my $pidFile = $Cfg->get('PidFile') || die "No 'pidfile' found here";
    my $uidFile = $Cfg->get('UidFile') || "";             # optional
    my $envPath = $Cfg->get('PathEnv') || $PathEnv;       # may be in cfg

    ## warn $Cfg->dump();  #DEBUG:

    ($uid, $gid) = $class->getUidGid( $uidFile )
	unless ( defined $uid and defined $gid );

    $uid   = undef unless ( defined($uid)   and length($uid)   );
    $gid   = undef unless ( defined($gid)   and length($uid)   );
    $umask = 022   unless ( defined($umask) and length($umask) );

    my $daemon      = new PTools::Proc::Daemonize;
    my $workingDir  = "/tmp";
    my $evListRef   = [ "TZ" ];

    my(@daemonArgs) = ( $uid,$gid, $workingDir, $umask,   $evListRef,
                        $envPath,  $logFile,    $pidFile );

    $daemon->runAs( $Debug->isSet(), @daemonArgs );

    my($stat,$err) = $daemon->status();
    $stat and die "Error: $err\n";

    return;
}

#-----------------------------------------------------------------------
# Server process configuration and parsing
#-----------------------------------------------------------------------

sub getConfig
{   my($class, $cfgFile) = @_;

    my $cfg = $CfgClass->new( $cfgFile );

    # And do some fixup on various config file paths
    # FIX: move this to "Cfg" class?? Probably...

    my $logFile  = $cfg->get('LogFile') || die "No 'logfile' found here";
    my $pidFile  = $cfg->get('PidFile') || die "No 'pidfile' found here";
    my $uidFile  = $cfg->get('UidFile') || "";             # optional

    if ($logFile and $logFile !~ m#^/#) {
	$cfg->set('LogFile', $Local->path('app_datdir', "gcs/$logFile") );
    }

    if ($pidFile and $pidFile !~ m#^/#) {
	$cfg->set('PidFile', $Local->path('app_datdir', "gcs/$pidFile") );
    }

    if ($uidFile and $uidFile !~ m#^/#) {
	$cfg->set('UidFile', $Local->path('app_datdir', "gcs/$uidFile") );
    }

    ## warn $cfg->dump();   # DEBUG:

    return $cfg;
}

#-----------------------------------------------------------------------
# Command-line options and arguments configuration and parsing
#-----------------------------------------------------------------------

sub parseCmdLine
{   my($class) = @_;

    # You will find that a lot of work is done here, and that
    # the work is broken into a lot of steps. The intent is 
    # to make it easier when subclassing this module.


    # 1) Configure options used to start the server daemon
    #
    my($usage, @optArgs) = $class->defineStartupOptions();

    # 2) Configure options used to signal a running daemon
    #
    ($usage, @optArgs) = $class->defineSignalOptions( $usage, @optArgs );


    # 3) Configure the option parser and parse the command-line
    #
    my $opts = $class->parseOptionsAndArgs( $usage, @optArgs );


    # 4) Validate the command-line options and arguments
    #
    $class->validateOptionsAndArguments( $opts );

    # 5) Validate the command-line SIGNAL options
    #
    $class->validateSignalOptions( $opts );
    

    # die $opts->dump();  # DEBUG:

    return $opts;
}

sub defineStartupOptions                           # Step 1 of 5 #
{   my($class) = @_;

    my $usage = <<"__EndOfUsage__";

 Usage: $BaseName <options>

    where <options> to start a server daemon include:
	-c <config_file>       -  specify alternate config file
	-D [<debug_level>]     -  set debug flag w/optional level
	-l <log_level>         -  specify starting logging level
	-h                     -  display usage and exit

__EndOfUsage__

    my(@optArgs) = ();

    push(@optArgs,
	      "help|?|h",             # help    flag
             "preview|p",             # preview flag
               "force|f",             # force   flag
       "debug|Debug|D|d:i",           # debug   flag:  -d [n] | -debug [n]
             "verbose|v+",            # verbose flag:  -v [-v...]

      "configFile|cfg|c=s",           # config file
            "logLevel|l=i",           # initial logging verbosity level
    );

    return( $usage, @optArgs );
}

sub defineSignalOptions                            # Step 2 of 5 #
{   my($class, $usage, @optArgs) = @_;


    $usage .= <<"__EndOfUsage__";
    additional <options> can be used to signal a running server:
	-logincr               -  increment current log level   (USR1)
	-logdecr               -  decrement current log level   (USR2)
	-logreset              -  reset to starting log level   (INT)
	-reconfig              -  reconfigure a running daemon  (HUP)
	-restart               -  restart a running daemon       n/a
	-shutdown              -  initiate graceful shutdown    (TERM)
	-quit                  -  abort (try -shutdown first)   (QUIT)
	-kill [{<n> | <name>}] -  send arbitrary signal (dflt is TERM)

__EndOfUsage__

    push(@optArgs, 
	# Signal handling switches. Each is mutually exculsive with 
	# any other option. Note that SIGTERM is "15" while Ctrl+\
	# is "3" (SIGQUIT). Both are supported by the GCS server and
	# are used to initiate a "graceful" shutdown of the daemon.
	# These are options to the startup command; however, they are
	# only effective if the GCS server is already running AND if
	# a user running the command has permission to sig the proc.
	#
	# Note that "-stop" sends SIGPIPE but "-STOP" sends SIGSTOP
        # (the first will hard abort the server, the second suspends
	# the server daemon until the 'fg' (foreground) cmd is used).
	# Confusing? Yep, so don't show this in the Usage help text.
	# -shutdown, -quit and -kill 9 are certainly sufficient here.
	# And yes, there are lots of variations on these themes.
	# Each of the following strings will signal a server process
	# and, in addition, "-kill [ { <n> | <name> } ]" works too.

	     "restart",         # completely restart daemon process

     "SIGHUP|sighup|hup|HUP|reload|reconfig",     # sig  1 (reread config file)
	    "SIGINT|sigint|int|INT|logreset",     # sig  2 (or Ctrl+c  with -D)
	"SIGQUIT|sigquit|quit|QUIT|quit",         # sig  3 (or Ctrl+\  with -D)
	     "SIGKILL|sigkill|KILL|kill:s",       # (SIGTERM is default signal)
	"SIGPIPE|sigpipe|pipe|PIPE|stop",         # sig 13 (abort server)
	"SIGTERM|sigterm|term|TERM|shutdown",     # sig 15 (graceful shutdown)
	"SIGUSR1|sigusr1|usr1|USR1|logincr",      # sig 16 (incr logging by 2)
	"SIGUSR2|sigusr2|usr2|USR2|logdecr",      # sig 17 (decr logging by 2)
	     "SIGCONT|sigcont|CONT|continue",     # sig 18 (resume suspended)
	     "SIGSTOP|sigstop|STOP|suspend",      # sig 19 (suspend job)
    );

    return( $usage, @optArgs );
}

sub parseOptionsAndArgs                            # Step 3 of 5 #
{   my($class, $usage, @optArgs) = @_;

    # Configure Getopt::Long, then collect and parse the ARGV array.
    # NOTE: If we will have "long options with a single dash" ("-debug"),
    # we must configure for either "no_bundling" or "bundling_override".

    my $opts = new PTools::Options();          # delay parsing @ARGV

  # $opts->config( "posix_default" );          # as if EV "POSIXLY_CORRECT" set
  # $opts->config( "no_bundling" );            # disable bundling entirely
    $opts->config( "bundling_override" );      # allow bundling AND long opts

    # Next, parse the command-line input

    $opts->parse( $usage, @optArgs );          # parse @ARGV via Getopt::Long
    
    $opts->abortOnError();                     # abort if any parsing errors

    return $opts;
}

sub validateOptionsAndArguments                    # Step 4 of 5 #
{   my($class, $opts) = @_;

    #-----------------------------------------------------------------------
    # Verify/validate the various possible option/argument combinations
    # Was "-d/-debug" and/or "-v/-verbose" used this time 'round? 
    #
    $opts->exitWithUsage() if $opts->help();   # exit if "-h" or "-help" used

    $Debug   = new PTools::Debug  ( $opts->get('debug')   );
    $Verbose = new PTools::Verbose( $opts->get('verbose') );

    $opts->set('debug',   $Debug  );           # turn attribute into an object
    $opts->set('verbose', $Verbose);           # turn attribute into an object

    #-----------------------------------------------------------------------
    # User entered option (-f filename) overrides default config file
    #
    $opts->set('configFile', $DefaultConfigFile)
	unless ( $opts->get('configFile') );

    #-----------------------------------------------------------------------
    # Note: "-l <n>" ("-logLevel <n>") implemented in 'initialize()' method
    # since we need to have an instantiated "config file" object first.
    #
    ### die "$BaseName: Error: -l switch not yet implemented"  
    ###	    if $opts->logLevel();

    #-----------------------------------------------------------------------
    # Stash objects for wide usage elsewhere

    $Local->set('app_optsObj',    $opts            );
    $Local->set('app_debugObj',   $opts->debug()   );
    $Local->set('app_verboseObj', $opts->verbose() );

    # warn $opts->dump();           # show contents of $opts object(s)
    # warn $Debug->dump()           if $Debug->isSet();
    # warn $Verbose->dump()         if $Verbose->isSet();

    return;
}

sub validateSignalOptions                          # Step 5 of 5 #
{   my($class, $opts) = @_;

    #-------------------------------------------------------------------
    # Do a special check to handle restart processing
    # Send a SIGTERM to the currently running daemon process
    # and then simply return to continue with server restart.

    if ( $opts->restart() ) {
	$class->signalServerPid( "TERM" );
	sleep 1;
	warn "$BaseName: restarting server process\n";
	return;
    }

    #-------------------------------------------------------------------
    my $optRef = $opts->opts();      # collect user-entered options
    my($sigCount, $optCount, $signal) = (0,0,"");

    foreach my $opt ( @$optRef ) {
	if ( $opt =~ /^SIGKILL/ ) {                 # special for 'sigkill':
	    $signal = $opts->SIGKILL() || "TERM";   # sig defaults to 15/TERM,
	    $signal = $1 if ($signal =~ /^(.+)$/);  # and detaint the signal
	    $sigCount++;
	} elsif ( $opt =~ /^SIG(\w+)/ ) {
	    $signal = $1;
	    $sigCount++;
	} else {
	    $optCount++;
	}
    }
    return unless ($sigCount);       # no signal opts? we're outta here.

    #-------------------------------------------------------------------
    # WARN: We have a signal option. All further logic in this
    # method will result in either a clean exit or an abort.
    # Nothing else returns from here to the end of this subroutine.
    #-------------------------------------------------------------------

    if ( ($optCount) or ($sigCount > 1) ) {
	warn "$BaseName: Error: signal options are mutually exclusive.\n";
	$opts->abortWithUsage();
    }

    # Okay, we have one signal opt. Let's figure out where to send it.
    # FIX: add nice helpful messages if no pid, signal fails, etc.

    $class->signalServerPid( $signal );

    exit( 0 );   ### if $sigOkay;         # signal sent! Just exit here.
}

#-----------------------------------------------------------------------
# Signal generation method to signal a running server daemon
#-----------------------------------------------------------------------

sub signalServerPid
{   my($class, $signal, $processId) = @_;

    $processId ||= $class->getServerPid( $BaseName );

    ## warn "DEBUG: attempting to send 'SIG$signal' to PID '$processId'\n";

    my $sigOkay = CORE::kill( $signal, $processId );

    return  if ($sigOkay);

    #-------------------------------------------------------------------
    # Oops. Something went wrong. If server not running and we're
    # in 'restart' mode it's not fatal

    if ($! and $! == EPERM) {
	warn "$BaseName: Error: no permission to signal server process\n";
    } elsif ($! and $! == ESRCH) {
	my $text = ( $processId ? " as pid=$processId" : "" );
	if ( $Opts and $Opts->restart() ) {
	    warn "$BaseName: Note: server not running$text\n";    # Note
	    return;
	} else {
	    warn "$BaseName: Error: server not running$text\n";   # Error
	}
    } elsif ($!) {
	warn "$BaseName: Error: can't send 'SIG$signal' to server: $!\n";
    }
    exit(-1);
}

#-----------------------------------------------------------------------
# Server config file access methods
#-----------------------------------------------------------------------

sub getServerPid
{   my($class, $BaseName) = @_;

    my $pidFile = $Local->path('app_datdir', "gcs/server.pid");

    if (! -f $pidFile ) {
	warn "$BaseName: Error: No 'pid file' found to check\n";
	warn "  ($pidFile)\n";
	exit(-1);

    } elsif (! -r _ ) {
	warn "$BaseName: Error: The 'pid file' is not readable\n";
	warn "  ($pidFile)\n";
	exit(-1);
    }

    local(*IN);
    open(IN, "<$pidFile") || die "$BaseName: Error: can't open '$pidFile': $!";
    my $processId = <IN>  || die "$BaseName: Error: can't read '$pidFile': $!";
    close(IN)             || die "$BaseName: Error: can't close '$pidFile': $!";
    chomp $processId;

    if ($processId =~ /^(\d+)$/) {           # verify (and detaint) the PID
	$processId = $1;
    } else {
	warn "$BaseName: Error: non-numeric PID '$processId' in 'pid file'\n";
	warn "  ($pidFile)\n";
	exit(-1);
    }

    return $processId;
}

sub getUidGid
{   my($class, $gcsUidGidFile ) = @_;

    # Here we actually get the Uid and Gid from the data file
    # AND set both effective and real uid/gid for this script.

    local(*IN);
    if (! open(IN, "<$gcsUidGidFile" )  ) {
	if ($! =~ /No such file/) {
	    warn "$BaseName: Warning: No 'uid' file: skip uid/gid checks.\n";
	    return;
	} else {
	    die "$BaseName: Error: Can't open $gcsUidGidFile: $!\n";
	}
    }

    my($line) = <IN>
	or die "$BaseName: Error: Can't read $gcsUidGidFile: $!\n";
    close(IN)  
	or die "$BaseName: Error: Can't close $gcsUidGidFile: $!\n";

    chomp( $line ); 
    my($uid, $gid) = split(":", $line);

    ($),$() = ($gid,$gid);         # set eff. and real gid
    ($>,$<) = ($uid,$uid);         # set eff. and real uid

    return( $uid, $gid );
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server - Generic network server model

=head1 VERSION

This document describes version 0.01, released November, 2005.

=head1 SYNOPSIS

 #!/opt/perl/bin/perl -T
 # 
 # File:  gcsServer.pl
 #
 use PTools::Local;
 use POE::Component::GCS::Server;

 $configFile = PTools::Local->param('app_cfgdir', "gcs/gcs.conf");

 exit( run POE::Component::GCS::Server( $configFile ) );

=head1 DESCRIPTION

This class is used to start a generic network server daemon.
To cleanly shutdown the server, send a SIGTERM to the process ID,
which can be accomplished by running the server startup script,
shown in the L<Synopsis|"SYNOPSIS"> section, above, with a
command-line option of '-shutdown'. Use the '-h' (or '--help')
option to see available options and arguments.

A configuration file is optional. Without this, default port
number(s) is/are specified for the TCP server(s). See 
L<POE::Component::GCS::Server::TCP> for configuration details.

This set of Generic Client/Server (GCS) classes implement a 
working example of a "Server | Controller | Subprocess"
pattern, which consists of 1) a network server, 2) a process 
manager and 3) a set of child processes that asynchronously 
perform long-running tasks.

=head2 Constructor

=over 4

=item run ( [ ConfigFile ] )

This is the only public method used to start the generic
server. The optional B<ConfigFile> parameter can be added to
specify an external file used to configure a the server. When
used, this is expected to be either a full or relative path 
to the file.

=back

=head2 Methods

None. The only public methods are those described above.

=head1 DEPENDENCIES

This class depends upon the following:

 POE (the Perl Object Environment),
 POE-Event-Message and
 PTools

=head1 SEE ALSO

For discussion and examples of using an external configuration file
see L<POE::Component::GCS::Server::Cfg>.
For discussion of client access, see L<POE::Component::GCS::Client>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

