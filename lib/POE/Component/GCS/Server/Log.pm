# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Log.pm
# Desc:  Generic logging facility
# Date:  Wed Feb 02 17:03:35 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::Log;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.02';
#our @ISA    = qw( );

##use FileHandle;

*new = \&spawn;

sub spawn
{   my($class, $logLevel) = @_;

    my $self = $Global::GLOBAL_LOGOBJ;
    return $self if $self;         # is a "singleton class"

    $Global::GLOBAL_LOGOBJ   = $class;
    $Global::GLOBAL_LOGLEVEL = $logLevel ||3;

    $|= 1;

    $class->write(4, "spawning Log service");

    ## autoflush STDOUT 1;
    ## autoflush STDERR 1;

    return $class;                 # return "$class" here, NOT "$self"
}

*log      = \&writeLog;
*write    = \&writeLog;
*writelog = \&writeLog;

sub writeLog
{   my($self,$verbose,$logMsg) = @_;

    # Since the REAL server runs as a daemon proc, it has already 
    # redirected STDOUT and STDERR to the log file. All we need to 
    # do here is format a time string and simply print the message.

    return if $verbose > $Global::GLOBAL_LOGLEVEL;

    print $self->formatDate();
    print " $logMsg\n";
    return;
}

*error     = \&writeWarn;
*warn      = \&writeWarn;
*writewarn = \&writeWarn;

sub writeWarn
{   my($self,$verbose,$warnMsg) = @_;

    # This method is intended for use within a child process run 
    # by the "POE::Component::GCS::Server::Queue" class. Child 
    # processes so run should NOT write ANY output to STDOUT and, 
    # instead, send any message to STDERR. This provides a method
    # similar to the "writeLog()" method used "everywhere else".

    return if $verbose > $Global::GLOBAL_LOGLEVEL;

    warn "$warnMsg\n";
    return;
}

*logLevel = \&getLogLevel;

sub formatDate   { time() }          # allow for simple subclassing.
sub getLogLevel  { $Global::GLOBAL_LOGLEVEL }
sub setLogLevel  { $Global::GLOBAL_LOGLEVEL  = ($_[1] ||3) }
sub incrLogLevel { $Global::GLOBAL_LOGLEVEL += ($_[1] ||3) }
sub decrLogLevel { $Global::GLOBAL_LOGLEVEL -= ($_[1] ||3) }
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Log - Generic server logging

=head1 VERSION

This document describes version 0.02, released February, 2005.

=head1 SYNOPSIS

  use POE::Component::GCS::Server::Log;
  spawn POE::Component::GCS::Server::Log ( LoggingLevel );

  $Log = "POE::Component::GCS::Server::Log";

  $Log->write( $command_string );
  

=head1 DESCRIPTION

This class is used to validate and dispatch commands within a generic 
network server daemon. To cleanly subclass, simply override the
B<dispatch> method. If the generic commands, described below, remain
implemented in the Maintenance and Proc classes, there is no need to
override the genericCommands method.

Note that this module is not event driven. The assumption is that
an application's logging function should be synchronous.
As such, this generic class is implemented to immediately write
messages to the system's log file and flush the log buffer if
necessary.

=head2 Constructor

=over 4

=item spawn ( [ LoggingLevel ] )

This creates a new generic server log object. Note
that the object created is implemented as a 'B<singleton>', 
meaning that any subsequent calls to this method will return
the original object created by the first call to this method.

The optional B<LoggingLevel> parameter can be added to
specify the amount of logging that will occur. By default,
the initial LoggingLevel is set to a value of B<3>.

=back

=head2 Methods

=over 4

=item log ( LogLevel, LogText )

=item write ( LogLevel, LogText )

This method writes the B<LogText> to the application's log file.
If the B<LogLevel> is I<greater> than the initial B<LoggingLevel>
specified when spawning this service, the message is not written
to the log file.

=over 4

=item LogLevel

This B<LogLevel> parameter is compared with the initial B<LoggingLevel>
to determine wheather the log message will be written or not.

=item LogText

This is a string of text written to the log file. Note that a date
is prepended to the message. By default, the date string is simply
the number returned by Perl's B<time()> function.

=back


=item error ( LogLevel, LogText )

=item warn ( LogLevel, LogText )

These methods are provided as a simple alternative to the
builtin Perl B<warn> function, in a manner compatible with
the above 'B<L<log>>' and 'B<L<write>>' methods, and the 
arguments are indentical to those described above.


=item formatDate ( )

This method is provided to simplify subclassing this module. All 
this method needs to do is return a formatted date string. This 
short example implements a complete subclass that changes the 
default date (prepended to each log message) with a foratted 
string.

 package My::Custom::Logger;
 use strict;
 use warnings;
 our @ISA = qw( POE::Component::GCS::Server::Log );

 use POE::Component::GCS::Server::Log;
 use Date::Format;

 $DateFormat = "%Y%m%d %H:%M:%S";      # 20050516 19:05:39

 sub formatDate { time2str( $DateFormat, time() ) }
 #_________________________
 1; # Required by require()


=item setLogLevel ( [ LoggingLevel ] )

=item incrLogLevel ( IncreaseBy )

=item decrLogLevel ( DecreaseBy )

These methods can be used to set, increment or decrement the
initial B<LoggingLevel> set when an object of this class was 
first instantiated. By default the B<LoggingLeve> is set to 3.
Other than that, usage should be obvious.

=item getLogLevel ( )

This method returns the B<LoggingLevel> currently in use.

=back

=head1 DEPENDENCIES

None currently.

=head1 SEE ALSO

For discussion of the generic server, see L<POE::Component::GCS::Server>.
For discussion of server configuration, see L<POE::Component::GCS::Server::Cfg>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2010 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
