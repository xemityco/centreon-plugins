#
# Copyright 2018 Centreon (http://www.centreon.com/)
#
# Centreon is a full-fledged industry-strength solution that meets
# the needs in IT infrastructure and application monitoring for
# service performance.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package cloud::prometheus::direct::kubernetes::mode::daemonsetstatus;

use base qw(centreon::plugins::templates::counter);

use strict;
use warnings;

my $instance_mode;

sub custom_status_perfdata {
    my ($self, %options) = @_;
    
    my $extra_label = '';
    if (!defined($options{extra_instance}) || $options{extra_instance} != 0) {
        $extra_label .= '_' . $self->{result_values}->{display};
    }
    
    $self->{output}->perfdata_add(label => 'desired' . $extra_label,
                                  value => $self->{result_values}->{desired});
    $self->{output}->perfdata_add(label => 'current' . $extra_label,
                                  value => $self->{result_values}->{current});
    $self->{output}->perfdata_add(label => 'available' . $extra_label,
                                  value => $self->{result_values}->{available});
    $self->{output}->perfdata_add(label => 'unavailable' . $extra_label,
                                  value => $self->{result_values}->{unavailable});
    $self->{output}->perfdata_add(label => 'up_to_date' . $extra_label,
                                  value => $self->{result_values}->{up_to_date});
    $self->{output}->perfdata_add(label => 'ready' . $extra_label,
                                  value => $self->{result_values}->{ready});
    $self->{output}->perfdata_add(label => 'misscheduled' . $extra_label,
                                  value => $self->{result_values}->{misscheduled});
}

sub custom_status_threshold {
    my ($self, %options) = @_;
    my $status = 'ok';
    my $message;

    eval {
        local $SIG{__WARN__} = sub { $message = $_[0]; };
        local $SIG{__DIE__} = sub { $message = $_[0]; };

        if (defined($instance_mode->{option_results}->{critical_status}) && $instance_mode->{option_results}->{critical_status} ne '' &&
            eval "$instance_mode->{option_results}->{critical_status}") {
            $status = 'critical';
        } elsif (defined($instance_mode->{option_results}->{warning_status}) && $instance_mode->{option_results}->{warning_status} ne '' &&
            eval "$instance_mode->{option_results}->{warning_status}") {
            $status = 'warning';
        }
    };
    if (defined($message)) {
        $self->{output}->output_add(long_msg => 'filter status issue: ' . $message);
    }

    return $status;
}

sub custom_status_output {
    my ($self, %options) = @_;

    return sprintf("nodes desired : %s, current : %s, available : %s, unavailable : %s, up-to-date : %s, ready : %s, misscheduled : %s",
        $self->{result_values}->{desired},
        $self->{result_values}->{current},
        $self->{result_values}->{available},
        $self->{result_values}->{unavailable},
        $self->{result_values}->{up_to_date},
        $self->{result_values}->{ready},
        $self->{result_values}->{misscheduled});
}

sub custom_status_calc {
    my ($self, %options) = @_;

    $self->{result_values}->{display} = $options{new_datas}->{$self->{instance} . '_display'};
    $self->{result_values}->{desired} = $options{new_datas}->{$self->{instance} . '_desired'};
    $self->{result_values}->{current} = $options{new_datas}->{$self->{instance} . '_current'};
    $self->{result_values}->{available} = $options{new_datas}->{$self->{instance} . '_available'};
    $self->{result_values}->{unavailable} = $options{new_datas}->{$self->{instance} . '_unavailable'};
    $self->{result_values}->{up_to_date} = $options{new_datas}->{$self->{instance} . '_up_to_date'};
    $self->{result_values}->{ready} = $options{new_datas}->{$self->{instance} . '_ready'};
    $self->{result_values}->{misscheduled} = $options{new_datas}->{$self->{instance} . '_misscheduled'};

    return 0;
}

sub set_counters {
    my ($self, %options) = @_;
    
    $self->{maps_counters_type} = [
        { name => 'daemonsets', type => 1, cb_prefix_output => 'prefix_daemonset_output', message_multiple => 'All daemonsets status are ok', skipped_code => { -11 => 1 } },
    ];

    $self->{maps_counters}->{daemonsets} = [
        { label => 'status', set => {
                key_values => [ { name => 'desired' }, { name => 'current' }, { name => 'up_to_date' },
                    { name => 'available' }, { name => 'unavailable' }, { name => 'ready' },
                    { name => 'misscheduled' }, { name => 'display' } ],
                closure_custom_calc => $self->can('custom_status_calc'),
                closure_custom_output => $self->can('custom_status_output'),
                closure_custom_perfdata => $self->can('custom_status_perfdata'),
                closure_custom_threshold_check => $self->can('custom_status_threshold'),
            }
        },
    ];
}

sub prefix_daemonset_output {
    my ($self, %options) = @_;

    return "Daemonset '" . $options{instance_value}->{display} . "' ";
}

sub new {
    my ($class, %options) = @_;
    my $self = $class->SUPER::new(package => __PACKAGE__, %options);
    bless $self, $class;
    
    $self->{version} = '1.0';
    $options{options}->add_options(arguments =>
                                {
                                  "daemonset:s"             => { name => 'daemonset', default => '.*' },
                                  "warning-status:s"        => { name => 'warning_status', default => '%{up_to_date} < %{desired}' },
                                  "critical-status:s"       => { name => 'critical_status', default => '%{available} < %{desired}' },
                                  "extra-filter:s@"         => { name => 'extra_filter' },
                                  "metric-overload:s@"      => { name => 'metric_overload' },
                                });
   
    return $self;
}

sub check_options {
    my ($self, %options) = @_;
    $self->SUPER::check_options(%options);
    
    $self->{metrics} = {
        'desired' => '^kube_daemonset_status_desired_number_scheduled$',
        'current' => '^kube_daemonset_status_current_number_scheduled$',
        'available' => '^kube_daemonset_status_number_available$',
        'unavailable' => '^kube_daemonset_status_number_unavailable$',
        'up_to_date' => '^kube_daemonset_updated_number_scheduled$',
        'ready' => '^kube_daemonset_status_number_ready$',
        'misscheduled' => '^kube_daemonset_status_number_misscheduled$',
    };
    foreach my $metric (@{$self->{option_results}->{metric_overload}}) {
        next if ($metric !~ /(.*),(.*)/);
        $self->{metrics}->{$1} = $2 if (defined($self->{metrics}->{$1}));
    }

    $instance_mode = $self;
    $self->change_macros();
}

sub change_macros {
    my ($self, %options) = @_;
    
    foreach (('warning_status', 'critical_status')) {
        if (defined($self->{option_results}->{$_})) {
            $self->{option_results}->{$_} =~ s/%\{(.*?)\}/\$self->{result_values}->{$1}/g;
        }
    }
}

sub manage_selection {
    my ($self, %options) = @_;

    $self->{daemonsets} = {};

    my $extra_filter = '';
    foreach my $filter (@{$self->{option_results}->{extra_filter}}) {
        $extra_filter .= ',' . $filter;
    }

    my $results = $options{custom}->query(queries => [ 'label_replace({__name__=~"' . $self->{metrics}->{desired} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "desired", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{current} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "current", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{available} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "available", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{unavailable} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "unavailable", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{up_to_date} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "up_to_date", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{ready} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "ready", "", "")',
                                                       'label_replace({__name__=~"' . $self->{metrics}->{misscheduled} . '",
                                                            daemonset=~"' . $self->{option_results}->{daemonset} .
                                                            '"' . $extra_filter . '}, "__name__", "misscheduled", "", "")' ]);
    
    foreach my $metric (@{$results}) {
        $self->{daemonsets}->{$metric->{metric}->{daemonset}}->{display} = $metric->{metric}->{daemonset};
        $self->{daemonsets}->{$metric->{metric}->{daemonset}}->{$metric->{metric}->{__name__}} = ${$metric->{value}}[1];
    }
    
    if (scalar(keys %{$self->{daemonsets}}) <= 0) {
        $self->{output}->add_option_msg(short_msg => "No daemonsets found.");
        $self->{output}->option_exit();
    }
}

1;

__END__

=head1 MODE

Check daemonset status.

=over 8

=item B<--daemonset>

Filter on a specific daemonset (Must be a regexp, Default: '.*')

=item B<--warning-status>

Set warning threshold for status (Default: '%{up_to_date} < %{desired}')
Can used special variables like: %{display}, %{desired}, %{current},
%{available}, %{unavailable}, %{up_to_date}, %{ready}, %{misscheduled}

=item B<--critical-status>

Set critical threshold for status (Default: '%{available} < %{desired}').
Can used special variables like: %{display}, %{desired}, %{current},
%{available}, %{unavailable}, %{up_to_date}, %{ready}, %{misscheduled}

=item B<--extra-filter>

Add a PromQL filter (Can be multiple)

Example : --extra-filter='name=~".*pretty.*"'

=item B<--metric-overload>

Overload default metrics name (Can be multiple, metric can be 'status')

Example : --metric-overload='metric,^my_metric_name$'

=back

=cut
