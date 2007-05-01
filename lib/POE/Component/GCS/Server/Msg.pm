# -*- Perl -*-
#
# File:  POE/Component/GCS/Server/Msg.pm
# Desc:  GCS 'simple network object' message class
# Date:  Thu Sep 29 11:34:52 2005
# Stat:  Prototype, Experimental
#
package POE::Component::GCS::Server::Msg;
use 5.008;
use strict;
use warnings;

our $PACK    = __PACKAGE__;
our $VERSION = '0.01';
our @ISA     = qw( POE::Event::Message );

use POE::Event::Message 0.10;      # now correctly returns 'call' result

sub new
{   my($class, $header, $body, $clientId) = @_;

    my $self = $class->SUPER::new( $header, $body );

    if (! defined $clientId) {               # $clientId is optional ...
	$self->setErr( 0,"" );               #     okay!
    } elsif ($clientId =~ /^\d+$/) {         # ... BUT must be all numeric
	$self->setErr( 0,"" );               #     okay!
    } elsif ($clientId =~ /^[A-Za-z]+$/) {   # ... OR must be all non-numeric
	$self->setErr( 0,"" );               #     okay!
    } else {                                 # ... OR it's an error
	$self->setErr(-1,"Invalid 'clientId' argument: must be alpha OR num");
    }
    return $self;
}

#-----------------------------------------------------------------------
#   'ClientId' header
#-----------------------------------------------------------------------

sub getClientId { $_[0]->get('ClientId')        }
sub setClientId { $_[0]->set('ClientId', $_[1]) }
sub delClientId { $_[0]->del('ClientId')        }

*isaUserMessage = \&userMessage;

sub userMessage                   # ALL numeric, via TCP interface
{   my($self) = @_;
    my $clientId = $self->get('ClientId');
    return 0 unless ($clientId and $clientId =~ /^\d+$/);
    return 1;
}

*isaSystemMessage = \&systemMessage;

sub systemMessage                 # NON-numeric, GCS generated
{   my($self) = @_;
    my $clientId = $self->get('ClientId');
    return 0 if ($clientId and $clientId =~ /\d/);
    return 1;
}
#_________________________
1; # Required by require()

__END__

=head1 NAME

POE::Component::GCS::Server::Msg - Subclass of POE::Event::Message 

=head1 SYNOPSIS

 use POE::Component::GCS::Server::Msg;

 $msgClass = "POE::Component::GCS::Server::Msg";

 $message  = $msgClass->new();
 $message  = $msgClass->new( undef, $messageBody, $clientId );

 $response = $msgClass->new( $message, $responseBody, $clientId );

=head1 DESCRIPTION

This subclass extends the parent class, L<POE::Event::Message>, with
'ClientId' methods specific to the Generic Client Server (GCS).

=head2 Constructor

=over 4

=item new ( Header, Body, ClientId ) 

This method extends the parent class constructor to include a
B<ClientId> argument. This is then used to determine whether
the message is a 'B<User Message>' or a 'B<System Message>'.

A B<numeric> value indicates a 'B<User Message>' that was
received by the GCS server daemon via a TCP interface.

A B<non-numeric> value indicates a 'B<System Message>' that
was generated internally by a GCS server event.

This distinction is useful in determining whether a given
'command message' will be dispatched to a given command handler
method. See L<POE::Component::GCS::Server::Cmd> for details.

=back


=head2 Methods

=over 4

=item userMessage ()

Based on the B<ClientId>: If value is B<numeric> then returns 'true'.

=item systemMessage ()

Based on the B<ClientId>: If value is B<non-numeric> then returns 'true'.

=back


=head1 DEPENDENCIES

This class uses the parent class L<POE::Event::Message>.

=head1 AUTHOR

Chris Cobb, E<lt>no spam [at] ccobb [dot] netE<gt>

=head1 COPYRIGHT

Copyright (c) 2005-2007 by Chris Cobb. All rights reserved.
This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
