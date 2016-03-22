use strict;
use warnings;

package Mojolicious::Plugin::DbicSchemaViewer {

    # VERSION:
    # ABSTRACT: ...

    use Mojo::Base 'Mojolicious::Plugin';
    use Moose::Role;
    use MooseX::AttributeShortcuts;
    use Types::Standard -types;
    use Redis::Fast;
    use Encode;
    use Try::Tiny;
    use namespace::autoclean;
    use experimental qw/postderef signatures/;

    has actual => (
        is => 'rw',
        lazy => 1,
        builder => 1,
        clearer => 1,
        predicate => 1,
    );
    has not_connected_since => (
        is => 'rw',
        isa => Int,
        init_arg => 1,
        clearer => 1,
        predicate => 1,
    );
    has attempt_reconnect_every => (
        is => 'ro',
        isa => Int,
        default => 15,
    );

    sub register($self, $app, $conf) {
        warn ref $self;

    }


    requires qw/server prefix default_expiry/;

    sub connection_name($self) { $self->prefix }

    sub _build_redis($self) {
        my $redis;
        try {
            $redis = Redis::Fast->new(server => $self->server, name => $self->connection_name);
        }
        catch { };
        return $redis;
    };

    around [qw/get get_utf8 set setex del/] => sub ($next, $self, $key, @args) {
        if(time - $self->has_not_connected_since > $self->attempt_reconnect_every) {

            $self->not_connected_since(time);

            if(!$self->has_redis) {
                $self->redis($self->_build_redis);

                if(defined $self->redis && $self->redis->ping) {
                    $self->clear_not_connected_since;
                }
            }
        }
        $key = join '.' => ($self->prefix, $key);
        try {
            $self->$next($key, @args);
        }
        catch {
            $self->clear_redis;
            $self->not_connected_since(time);
            return undef;
        };
    };

    sub get_utf8($self, $key) {
        return decode('UTF-8', $self->redis->get($key));
    }
    sub get($self, $key) {
        return $self->redis->get($key);
    }
    sub set($self, $key, $value) {
        return $self->redis->set($key, $value);
    }

    # @data can be 1 or 2: the last item is always the value.
    # expiration time is optional, but is the first item (if there are two)
    # this is keep the order of arguments for redis setex
    sub setex($self, $key, @data) {
        my $value = pop @data;
        my $expiry = pop @data || $self->default_expiry;

        return $self->redis->setex($key, $expiry, $value);
    }

    sub del($self, $key) {
        return $self->redis->del($key);
    }


}

1;

__END__

=pod

=head1 SYNOPSIS

    use Mojolicious::Plugin::DbicSchemaViewer;

=head1 DESCRIPTION

Redis::Fast::Sweeten is ...

=head1 SEE ALSO

=cut
