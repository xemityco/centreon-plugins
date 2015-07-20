###############################################################################
# Copyright 2005-2015 CENTREON
# Centreon is developped by : Julien Mathis and Romain Le Merlus under
# GPL Licence 2.0.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation ; either version 2 of the License.
#
# This program is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, see <http://www.gnu.org/licenses>.
#
# Linking this program statically or dynamically with other modules is making a
# combined work based on this program. Thus, the terms and conditions of the GNU
# General Public License cover the whole combination.
#
# As a special exception, the copyright holders of this program give CENTREON
# permission to link this program with independent modules to produce an timeelapsedutable,
# regardless of the license terms of these independent modules, and to copy and
# distribute the resulting timeelapsedutable under terms of CENTREON choice, provided that
# CENTREON also meet, for each linked independent module, the terms  and conditions
# of the license of that module. An independent module is a module which is not
# derived from this program. If you modify this program, you may extend this
# exception to your version of the program, but you are not obliged to do so. If you
# do not wish to do so, delete this exception statement from your version.
#
# For more information : contact@centreon.com
# Authors : Mathieu Cinquin <mcinquin@centreon.com>
#
####################################################################################

package apps::docker::mode::containerstate;

use base qw(centreon::plugins::mode);

use strict;
use warnings;
use centreon::plugins::httplib;
use JSON;
use centreon::plugins::statefile;
use Digest::MD5 qw(md5_hex);

my $thresholds = {
    state => [
        ['Running', 'OK'],
        ['Paused', 'WARNING'],
        ['Restarting', 'WARNING'],
        ['OOMKilled', 'CRITICAL'],
        ['Dead', 'CRITICAL'],
        ['Exited', 'CRITICAL'],
    ],
};

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;

    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
        {
            "hostname:s"                => { name => 'hostname' },
            "port:s"                    => { name => 'port', default => '2376'},
            "proto:s"                   => { name => 'proto', default => 'https' },
            "urlpath:s"                 => { name => 'url_path', default => '/' },
            "name:s"                    => { name => 'name' },
            "id:s"                      => { name => 'id' },
            "credentials"               => { name => 'credentials' },
            "username:s"                => { name => 'username' },
            "password:s"                => { name => 'password' },
            "ssl:s"                     => { name => 'ssl', },
            "cert-file:s"               => { name => 'cert_file' },
            "key-file:s"                => { name => 'key_file' },
            "cacert-file:s"             => { name => 'cacert_file' },
            "timeout:s"                 => { name => 'timeout', default => '3' },
            "threshold-overload:s@"     => { name => 'threshold_overload' },
            "show-cache"                => { name => 'show_cache' },
        });

    $self->{container_id_selected} = [];
    $self->{statefile_cache} = centreon::plugins::statefile->new(%options);

    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::init(%options);

    if (!defined($self->{option_results}->{hostname})) {
        $self->{output}->add_option_msg(short_msg => "Please set the hostname option");
        $self->{output}->option_exit();
    }

    if ((defined($self->{option_results}->{credentials})) && (!defined($self->{option_results}->{username}) || !defined($self->{option_results}->{password}))) {
        $self->{output}->add_option_msg(short_msg => "You need to set --username= and --password= options when --credentials is used");
        $self->{output}->option_exit();
    }

    if ((defined($self->{option_results}->{name})) && ($self->{option_results}->{name} eq '')) {
        $self->{output}->add_option_msg(short_msg => "You need to specify the name option");
        $self->{output}->option_exit();
    }

    if ((defined($self->{option_results}->{id})) && ($self->{option_results}->{id} eq '')) {
        $self->{output}->add_option_msg(short_msg => "You need to specify the id option");
        $self->{output}->option_exit();
    }

    $self->{overload_th} = {};
    foreach my $val (@{$self->{option_results}->{threshold_overload}}) {
        if ($val !~ /^(.*?),(.*?),(.*)$/) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload option '" . $val . "'.");
            $self->{output}->option_exit();
        }
        my ($section, $status, $filter) = ($1, $2, $3);
        if ($self->{output}->is_litteral_status(status => $status) == 0) {
            $self->{output}->add_option_msg(short_msg => "Wrong treshold-overload status '" . $val . "'.");
            $self->{output}->option_exit();
        }
        $self->{overload_th}->{$section} = [] if (!defined($self->{overload_th}->{$section}));
        push @{$self->{overload_th}->{$section}}, {filter => $filter, status => $status};
    }

    $self->{statefile_cache}->check_options(%options);
}

sub get_severity {
    my ($self, %options) = @_;
    my $status = 'UNKNOWN'; # default

    if (defined($self->{overload_th}->{$options{section}})) {
        foreach (@{$self->{overload_th}->{$options{section}}}) {
            if ($options{value} =~ /$_->{filter}/i) {
                $status = $_->{status};
                return $status;
            }
        }
    }
    foreach (@{$thresholds->{$options{section}}}) {
        if ($options{value} =~ /$$_[0]/i) {
            $status = $$_[1];
            return $status;
        }
    }
    return $status;
}

sub manage_selection {
    my ($self, %options) = @_;

    # init cache file
    my $has_cache_file = $self->{statefile_cache}->read(statefile => 'cache_json_' . $self->{option_results}->{hostname}  . '_' . $self->{option_results}->{port} . '_' . $self->{mode});
    if (defined($self->{option_results}->{show_cache})) {
        $self->{output}->add_option_msg(long_msg => $self->{statefile_cache}->get_string_content());
        $self->{output}->option_exit();
    }

    my $timestamp_cache = $self->{statefile_cache}->get(name => 'last_timestamp');
    $self->reload_cache();
    $self->{statefile_cache}->read();

    my $all_containers = $self->{statefile_cache}->get(name => 'all_containers');
    foreach my $val (@{$all_containers}) {
        while( my ($containername,$containerid) = each(%{$val}) ) {
            if ($containername eq $self->{option_results}->{name}) {
                $self->{container_id_selected} = $containerid;
                last;
            }
        }
    }

    if (!defined($self->{container_id_selected})) {
        $self->{output}->add_option_msg(short_msg => "No container found for name '" . $self->{option_results}->{name} . "' (maybe you should reload cache file).");
        $self->{output}->option_exit();
    }

    return $self->{container_id_selected};
}

sub reload_cache {
    my ($self) = @_;
    my $datas = {};

    $datas->{last_timestamp} = time();

    my $jsoncontent;

    $self->{option_results}->{url_path} = $self->{option_results}->{url_path}."containers/json";
    my $query_form_get = { all => 'true' };
    $jsoncontent = centreon::plugins::httplib::connect($self, query_form_get => $query_form_get, connection_exit => 'critical');

    my $json = JSON->new;

    my $webcontent;

    eval {
        $webcontent = $json->decode($jsoncontent);
    };

    if ($@) {
        $self->{output}->add_option_msg(short_msg => "Can't construct cache...");
        $self->{output}->option_exit();
    }

    foreach my $val (@$webcontent) {
        my $containername = $val->{Names}->[0];
        $containername =~ s/^\///;
        my %container_link = ($containername => $val->{Id});
        my $container_link_ref = \%container_link;
        push @{$datas->{all_containers}}, $container_link_ref;
    }

    if (scalar(@{$datas->{all_containers}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "Can't construct cache...");
        $self->{output}->option_exit();
    }

    $self->{statefile_cache}->write(data => $datas);
}


sub run {
    my ($self, %options) = @_;

    my $jsoncontent;

    if (defined($self->{option_results}->{id})) {
        $self->{option_results}->{url_path} = "/containers/".$self->{option_results}->{id}."/json";
        $jsoncontent = centreon::plugins::httplib::connect($self, connection_exit => 'critical');
    } elsif (defined($self->{option_results}->{name})) {
        $self->manage_selection();
        $self->{option_results}->{url_path} = "/containers/".$self->{container_id_selected}."/json";
        $jsoncontent = centreon::plugins::httplib::connect($self, connection_exit => 'critical');
    } else {
        $self->{option_results}->{url_path} = "/containers/json";
        my $query_form_get = { all => 'true' };
        $jsoncontent = centreon::plugins::httplib::connect($self, query_form_get => $query_form_get, connection_exit => 'critical');
    }

    my $json = JSON->new;

    my $webcontent;

    eval {
        $webcontent = $json->decode($jsoncontent);
    };

    if ($@) {
        $self->{output}->add_option_msg(short_msg => "Cannot decode json response");
        $self->{output}->option_exit();
    }

    my ($result, $containername);
    my $exit = 'OK';

    if (defined($self->{option_results}->{id}) || defined($self->{option_results}->{name})) {
        while ( my ($keys,$values) = each(%{$webcontent->{State}})) {
            if ($values eq 'true') {
                $result = $keys;
                $containername = $webcontent->{Name};
                $containername =~ s/^\///;
                last;
            }
        }

        $exit = $self->get_severity(section => 'state', value => $result);
        $self->{output}->output_add(severity => $exit,
                                    short_msg => sprintf("Container %s is %s", $containername, $result));
    } else {
        $self->{output}->output_add(severity => 'OK',
                                    short_msg => sprintf("All containers are in Running state"));

        my ($nbrunning,$nbpaused,$nbexited) = '0';

        foreach my $val (@$webcontent) {
            $containername = $val->{Names}->[0];
            $containername =~ s/^\///;

            if (($val->{Status} =~ m/^Up/) && ($val->{Status} =~ m/^(?:(?!Paused).)*$/)) {
                $result = 'Running';
                $nbrunning++;
            } elsif ($val->{Status} =~ m/^Exited/) {
                $result = 'Exited';
                $nbexited++;
            } elsif ($val->{Status} =~ m/\(Paused\)$/) {
                $result = 'Paused';
                $nbpaused++;
            }

            my $tmp_exit = $self->get_severity(section => 'state', value => $result);
            $exit = $self->{output}->get_most_critical(status => [ $tmp_exit, $exit ]);
            if (!$self->{output}->is_status(value => $tmp_exit, compare => 'OK', litteral => 1)) {
                $self->{output}->output_add(long_msg => sprintf("Containers %s is in %s state",
                                                                $containername, $result));
            }
        }

        if ($exit ne 'OK') {
            $self->{output}->output_add(severity => $exit,
                                        short_msg => sprintf("Some containers are in wrong state"));
        }
        $self->{output}->perfdata_add(label => "running",
                                      value => $nbrunning,
                                      min => 0,
                                     );
        $self->{output}->perfdata_add(label => "paused",
                                      value => $nbpaused,
                                      min => 0,
                                     );
        $self->{output}->perfdata_add(label => "exited",
                                      value => $nbexited,
                                      min => 0,
                                     );
    }

    $self->{output}->display();
    $self->{output}->exit();

}

1;

__END__

=head1 MODE

Check Container's state

=over 8

=item B<--hostname>

IP Addr/FQDN of Docker's API

=item B<--port>

Port used by Docker's API (Default: '2576')

=item B<--proto>

Specify https if needed (Default: 'https')

=item B<--urlpath>

Set path to get Docker's container information (Default: '/')

=item B<--id>

Specify one container's id

=item B<--name>

Specify one container's name

=item B<--credentials>

Specify this option if you access webpage over basic authentification

=item B<--username>

Specify username

=item B<--password>

Specify password

=item B<--ssl>

Specify SSL version (example : 'sslv3', 'tlsv1'...)

=item B<--cert-file>

Specify certificate to send to the webserver

=item B<--key-file>

Specify key to send to the webserver

=item B<--cacert-file>

Specify root certificate to send to the webserver

=item B<--timeout>

Threshold for HTTP timeout (Default: 3)

=item B<--threshold-overload>

Set to overload default threshold values (syntax: section,status,regexp)
It used before default thresholds (order stays).
Example: --threshold-overload='state,CRITICAL,^(?!(Paused)$)'

=back

=cut
