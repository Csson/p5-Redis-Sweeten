use 5.20.0;
use strict;
use warnings;

package Redis::Fast::Sweeten {

    # ABSTRACT: ...

    use Moose::Role;
    use MooseX::AttributeShortcuts;
    use Types::Standard -types;
    use Redis::Fast;
    use Encode;
    use Try::Tiny;
    use namespace::autoclean;
    use experimental qw/postderef signatures/;

    has redis => (
        is => 'ro',
        lazy => 1,
        builder => 1,
    );

    requires qw/server prefix default_expiry/;

    sub connection_name($self) { $self->prefix }

    sub _build_redis($self) {
        my $redis;
        try {
            $redis = Redis::Fast->new(server => $self->server, name => $self->connection_name);
        }
        catch {
            warn 'Cannot connect to redis!';
        };
        return $redis;
    };

    around [qw/get get_utf8 set setex del/] => sub ($next, $self, $key, @args) {
        if(!defined $self->redis) {
            return undef;
        }
        $key = join '.' => ($self->prefix, $key);
        $self->$next($key, @args);
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

    use Redis::Fast::Sweeten;

=head1 DESCRIPTION

Redis::Fast::Sweeten is ...

=head1 SEE ALSO

=cut
