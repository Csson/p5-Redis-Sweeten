use 5.20.0;
use warnings;

package Mojolicious::Plugin::RedisHandler;

our $VERSION = '0.0100';
# ABSTRACT: ...

    use Mojo::Base 'Mojolicious::Plugin';
    use Class::Method::Modifiers;
    use Types::Standard -types;
    use Redis::Fast;
    use Encode;
    use MIME::Base64 qw/encode_base64 decode_base64/;
    use Try::Tiny;
    use namespace::autoclean;
    use experimental qw/postderef signatures/;

    has not_connected_since => undef;
    has attempt_reconnect_every => 15;
    has prefix => undef;
    has separator => ':';
    has database => 0;
    has connection_name => undef;
    has default_expiry => 900;
    has server => undef;
    has actual => undef;

    sub register($self, $app, $conf) {
        if(!exists $conf->{'server'}) {
            die "M::P::RedisHandler: mandatory configuration 'server' is missing";
        }
        $self->server($conf->{'server'});

        if(exists $conf->{'attempt_reconnect_every'}) {
            if($conf->{'attempt_reconnect_every'} =~ m{\D} || $conf->{'attempt_reconnect_every'} < 0) {
                die "M::P::RedisHandler: mandatory configuration 'attempt_reconnect_every' must be non-negative integer (was $conf->{'attempt_reconnect_every'})";
            }
            $self->attempt_reconnect_every($conf->{'attempt_reconnect_every'});
        }

        if(exists $conf->{'prefix'}) {
            $self->prefix($conf->{'prefix'});
        }
        if(exists $conf->{'connection_name'}) {
            $self->connection_name($conf->{'connection_name'});
        }
        if(exists $conf->{'default_expiry'}) {
            $self->default_expiry($conf->{'default_expiry'});
        }
        if(exists $conf->{'separator'}) {
            $self->separator($conf->{'separator'});
        }
        $self->database($conf->{'database'});

        $self->actual($self->_build_redis);

        my $handler_name = $conf->{'helper'} || 'redis';
        $app->helper($handler_name => sub { $self });

        return $self;
    }

    sub _build_redis($self) {
        my $redis;
        try {
            $redis = Redis::Fast->new(server => $self->server, name => $self->connection_name);
        }
        catch { };
        return $redis;
    };

    around [qw/get get_utf8 set setex del/] => sub ($next, $self, $key, @args) {
        warn ">>$key";
        if(!defined $self->actual && defined $self->not_connected_since && time - $self->not_connected_since > $self->attempt_reconnect_every) {
            $self->actual($self->_build_redis);

            if(defined $self->actual && $self->actual->ping) {
                $self->not_connected_since(undef);
            }
            else {
                $self->not_connected_since(time);
            }
        }

        $key = encode_base64 join ('.' => (defined $self->prefix ? $self->prefix : (), $key)), '';
        try {
            return $self->$next($key, @args);
        }
        catch {
            warn 'catched!' . $_;
            $self->not_connected_since(time);
            $self->actual(undef);
            return undef;
        };
    };

    sub get_utf8($self, $key) {
        return decode('UTF-8', $self->actual->get($key));
    }
    sub get($self, $key) {
        return $self->actual->get($key);
    }
    sub set($self, $key, $value) {
        return $self->actual->set($key, $value);
    }

    # @data can be 1 or 2: the last item is always the value.
    # expiration time is optional, but is the first item (if there are two)
    # this is keep the order of arguments for redis setex
    sub setex($self, $key, @data) {
        my $value = pop @data;
        my $expiry = pop @data || $self->default_expiry;

        return $self->actual->setex($key, $expiry, $value);
    }

    sub del($self, $key) {
        return $self->actual->del($key);
    }



1;

__END__

=pod

=head1 SYNOPSIS

    use Mojolicious::Plugin::RedisHandler;

=head1 DESCRIPTION

Mojolicious::Plugin::RedisHandler is ...

=head1 SEE ALSO

=cut
