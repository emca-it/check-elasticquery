#!/usr/bin/perl

# Author: 	Adam Miaskiewicz
# 			    EMCA S.A.

# Dependencies for Centos 7:
# yum install perl-Monitoring-Plugin perl-libwww-perl perl-LWP-Protocol-https perl-JSON perl-String-Escape

# Timestamp examples:
# -T 'now/h:now-1h/h' - events from latest hour rounded to 0 minute. When you check at 15:50 then it check 14:00-15:00.
# -T 'now:now-1h' - events from latest hour.  When you check at 15:50 then it check 14:50-15:50.
# -T 'now:now-1h' - events from latest hour.  When you check at 15:50 then it check 14:50-15:50.
# -T '1540482600:1540479000' events in defined timestamp range.
# Default 'now/now-1d' - vents from latest 24 hours (1 day).

##############################################################################
# prologue

use strict;
use warnings;

use File::Basename qw(dirname);
use Cwd  qw(abs_path);
use lib dirname(dirname abs_path $0) . '/lib';

use Monitoring::Plugin;
use LWP::UserAgent;
use JSON;
use Data::Dumper;
use String::Escape qw( backslash );

use vars qw($VERSION $PROGNAME  $verbose $warn $critical $timeout $result);
$VERSION = '0.1';

# get the base name of this script for use in the examples
use File::Basename;
$PROGNAME = basename($0);

##############################################################################
# define and get the command line options.
#   see the command line option guidelines at 
#   https://nagios-plugins.org/doc/guidelines.html#PLUGOPTIONS


# Instantiate Nagios::Monitoring::Plugin object (the 'usage' parameter is mandatory)
my $p = Monitoring::Plugin->new(
    usage => "Usage: %s -U|--url=<url> -i|--index=<index> 
    [ -q|--query=<json query> ]
    [ -S|--search=<saved search> ]
    [ -T|--timerange=<lte:gte> ]
    [--timefield=<time field> ]
    [ -c|--critical=<critical threshold> ] 
    [ -w|--warning=<warning threshold> ]
    [ -t <timeout>]
    [ -v|--verbose ]",
    version => $VERSION,
	license => "Apache License 2.0, see LICENSE for more details.",
    blurb => 'This plugin check Elasticsearch query total documents. It is aimed to work
with Energy Logserver, OP5 Log Analytics and is supposed to work with
opensource Elasticsearch and x-pack.', 
	extra => "Date match format for timerange option: https://www.elastic.co/guide/en/elasticsearch/reference/current/common-options.html#date-math

THRESHOLDs for -w and -c are specified 'min:max' or 'min:' or ':max'
(or 'max'). If specified '\@min:max', a warning status will be generated
if the count *is* inside the specified range.
See more threshold examples at http
  : // nagiosplug
  . sourceforge
  . net / developer-guidelines
  . html    #THRESHOLDFORMAT
  Examples:
  $PROGNAME -w 10 -c 18 Returns a warning
  if the resulting number is greater than 10,
  or a critical error
  if it is greater than 18.
  $PROGNAME -w 10 : -c 4 : Returns a warning
  if the resulting number is less than 10,
  or a critical error
  if it is less than 4.
  "
);

# Define and document the valid command line options
# usage, help, version, timeout and verbose are defined by default.

$p->add_arg(
	spec => 'warning|w=s',

	help => 
qq{-w, --warning=INTEGER:INTEGER
   Minimum and maximum scan freshness in days, outside of which a
   warning will be generated.  If omitted, no warning is generated.},
);

$p->add_arg(
	spec => 'critical|c=s',
	help => 
qq{-c, --critical=INTEGER:INTEGER
   Minimum and maximum scan freshness in days, outside of
   which a critical will be generated. },
);


$p->add_arg(
	spec => 'url|U=s',
	required => 1,
	help => 
qq{-U, --url=string
    Elasticsearch API URL. It allows basic-auth http[s]://[<username>:<password>]\@127.0.0.1:9200},
);

$p->add_arg(
	spec => 'search|S=s',
	help => 
qq{-S, --search=string
    Elasticsearch saved search. },
);

$p->add_arg(
	spec => 'documents|D=i',
	default => 0,
	help => 
qq{-D, --documents=string
    Show X documents. Default is 0.'},
);

$p->add_arg(
	spec => 'name|N=s',
	default => 'Total documents',
	help => 
qq{-S, --search=string
    Output name. Show output with defined name. Default is 'Total documents'.},
);

$p->add_arg(
	spec => 'timerange|T=s',
	default => "now:now-1d",
	help => 
qq{-T, --timerange=string
    Query filter time range "<lte>:<gte>". You can use UNIX timestamp or date match format. Default is 24 hours. },
);

$p->add_arg(
	spec => 'timefield=s',
	default => "\@timestamp",
	help => 
qq{--timefield=string
    Time range field. Default is \@timestamp. },
);

$p->add_arg(
	spec => 'index|i=s',
	required => 1,
	help => 
qq{-i, --index=string
    Elasticsearch index. },
);

$p->add_arg(
	spec => 'query|q=s',
	help => 
qq{-q, --query=string
    Execute this query in Elasticsearch. },
);


# Parse arguments and process standard ones (e.g. usage, help, version)
$p->getopts;

##############################################################################
# check stuff.


unless ( not defined $p->opts->search && not defined $p->opts->timerange ) {
	$p->plugin_exit(CRITICAL, "Define timerange for the saved search");
}

if ( $p->opts->timerange ne 'now:now-1d' && defined $p->opts->query ) {
	$p->plugin_exit(CRITICAL, "You can't use timerange with defined query");
}

if ( defined $p->opts->query && defined $p->opts->search ) {
	$p->plugin_exit(CRITICAL, "Query and saved search cann't be defined both");
}

if ( $p->opts->verbose ) {
		print "Url: ".$p->opts->url."\n" if defined $p->opts->url;
		print "Index: ".$p->opts->index."\n" if defined $p->opts->index;
		print "Search: ".$p->opts->search."\n" if defined $p->opts->search;
		print "Timerange: ".$p->opts->timerange."\n" if defined $p->opts->timerange;
		print "Timefield: ".$p->opts->timefield."\n" if defined $p->opts->timefield;
		print "Query: ".$p->opts->query."\n" if defined $p->opts->query;
}

my $query;
my $index;
my @timestamp = split(/:/, $p->opts->timerange) if (defined $p->opts->timerange);
if (defined $p->opts->search) {
	$query = '{"query":{"query_string":{"query":"'.$p->opts->search.'"}}}';
	$index = '.kibana';
}
else
{
	if (not defined $p->opts->query) {
		$query = '{ "size": 0, "query": { "bool": { "must": [ { "query_string": { "query": "*" } }, { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
	} else {
		$query = $p->opts->query;
	}
	
	$index = $p->opts->index;
}

my $total;
my $get = getSearch($p->opts->url, $index, $query);

if (defined $p->opts->search) {

	my $meta = decode_json($get->{hits}->{hits}[0]->{_source}->{search}->{kibanaSavedObjectMeta}->{searchSourceJSON}) if defined $get->{hits}->{hits}[0];
	if(keys $meta) {
		$get = getSearch($p->opts->url, $p->opts->index, '{ "size": '.$p->opts->documents.', "query": { "bool": { "must": [ { "query_string": { "query": "' . backslash($meta->{query}->{query}) . '" } }, { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }');		
	} else {
		$p->plugin_exit(CRITICAL, "Saved query not found");
	}
}

if(defined $get && keys $get->{hits}) {
	$total = $get->{hits}->{total};
	print Dumper($get) if ( $p->opts->verbose );
} else {
	$p->plugin_exit(CRITICAL, "Can not parse query");
}

##############################################################################
# check the result against the defined warning and critical thresholds,
# output the result and exit

# Set threshold
my $threshold = $p->set_thresholds(warning => $p->opts->warning, critical => $p->opts->critical);

# Set perfdata
$p->add_perfdata(
  label => "total",
  value => $total,
  threshold => $threshold
);

# Exit and return code
$Data::Dumper::Terse=1;
$p->plugin_exit($p->check_threshold(check => $total), $p->opts->name.": ${total}". (($p->opts->documents)>0?sprintf("\n".Dumper $get->{hits}->{hits}):'' ));

#### Subrutines
sub getSearch {
	my ($url, $index, $body) = @_;

	# UserAgent
	my $ua = LWP::UserAgent->new;
	$ua->agent($PROGNAME."/0.1");
	$ua->timeout($p->opts->timeout);
	# Create a request
	my $req;
	$req = HTTP::Request->new(POST => $url.'/'.$index.'/_search');
	$req->content_type('application/json');
	$req->content($body);

	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);

	# Check the outcome of the response
	my $json = JSON->new;

	$p->plugin_exit(CRITICAL, $res->message) if ($res->is_success == 0);
	
	return $json->decode($res->content) if ($res->is_success == 1);
	
	return undef;
}
