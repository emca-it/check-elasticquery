#!/usr/bin/perl

# Author:       Adam Miaskiewicz
#               EMCA S.A.
# Project URL: https://github.com/emca-it/check-elasticquery

# Work with Elasticsearch 7
# Dependencies for Centos 7:
# yum install perl-Monitoring-Plugin perl-libwww-perl perl-LWP-Protocol-https perl-JSON perl-String-Escape

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
$VERSION = '1.0.0';

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
    [ -q|--query=<lucene query> ]
    [ -j|--json]
    [ -S|--search=<saved search> ]
    [ -T|--timerange=<lte:gte> ]
    [--timefield=<time field> ]
    [ -D|--documents=<number of latest documents to show> ]
    [ -f|--fields=<fields to show> ]
    [ -l|--length=<max field length> ]
    [ -N|--name=<output string> ]
    [ -c|--critical=<critical threshold> ]
    [ -w|--warning=<warning threshold> ]
    [ --hidecurly ]
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
        spec => 'fields|f=s',
        help =>
qq{-S, --search=string
    Fields to show with Document option. },
);

$p->add_arg(
        spec => 'documents|D=i',
        default => 0,
        help =>
qq{-D, --documents=string
    Show X documents. Default is 0.'},
);

$p->add_arg(
        spec => 'length|l=i',
        default => 255,
        help =>
qq{-l, --length=string
    Maximum message length. Default is 255.'},
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
        default => '*',
        help =>
qq{-i, --index=string
    Elasticsearch index. },
);

$p->add_arg(
        spec => 'query|q=s',
        help =>
qq{-q, --query=string
    Execute this lucene query in Elasticsearch. },
);

$p->add_arg(
        spec => 'json|j',
        help =>
qq{-j, --json
    Use json intead of lucene syntax. },
);

$p->add_arg(
        spec => 'hidecurly',
        help =>
qq{--hidecurly
    Hide curly brackets in results. },
);

$p->add_arg(
        spec => 'oneliner',
        help =>
qq{--oneliner
    Show one document in first line. },
);


# Parse arguments and process standard ones (e.g. usage, help, version)
$p->getopts;

##############################################################################
# check stuff.

unless ( not defined $p->opts->search && not defined $p->opts->timerange ) {
	$p->plugin_exit(CRITICAL, "Define timerange for the saved search");
}

if(defined $p->opts->oneliner) {
	if($p->opts->documents > 1) {
		$p->plugin_exit(CRITICAL, "Oneliner is blocked for one document only.");
	}
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
my $sort = $p->opts->documents>0?'"sort" : [ { "'.$p->opts->timefield.'" : {"order" : "desc"}} ],':'';
my $get;

# If search option is used, get the saved search for kibana index.
if (defined $p->opts->search) {
	$query = '{ "query": { "bool": { "must": [ { "match": { "search.title": "'.$p->opts->search.'" } } ] }}}';
	$index = '.kibana';
	$get = getSearch($p->opts->url, $index, $query);
}

my $raw_query;
# If query option is used, get the raw query from the query argument
# raw_query is set only if json option is not used.
if (defined $p->opts->query) {
	if (not defined $p->opts->json) {
		$raw_query = '{ "query_string": { "query": "'.$p->opts->query.'", "analyze_wildcard": true, "default_field": "*" } },';
		if($p->opts->documents > 0) {
			$query =  '{ "size": '.$p->opts->documents.', '.$sort.'"query": { "bool": { "must": [ '.$raw_query.' { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
		} else {
			$query =  '{ "query": { "bool": { "must": [ '.$raw_query.' { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
		}
	} else {
		# for json query, raw_query is undefined
		$query = $p->opts->query;
	}
}

# if query and search are not defined, fire default all match query. This will return doc count in the time range
if (not defined $p->opts->query && not defined $p->opts->search) {
	$query = '{ "query": { "bool": { "must": [ { "query_string": { "query": "*" } }, { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
}

# reset the index to the value from command line argument as it might have been set to '.kibana' above
$index = $p->opts->index;

# If saved search is to be used, check for raw_query. If raw_query is present, replace saved search query with the raw_query.
if (defined $p->opts->search && not defined $p->opts->json) {
	print Dumper($get->{hits}->{hits}[0]) if($p->opts->verbose);
	my $meta = decode_json($get->{hits}->{hits}[0]->{_source}->{search}->{kibanaSavedObjectMeta}->{searchSourceJSON}) if defined $get->{hits}->{hits}[0];

	if(ref $meta eq ref {}) {
		my $indexID = $meta->{index};

		# ES 7. meta.index is not present. Use meta.indexRefName to get the indexID from the references
		if(not defined $indexID) {
			print "meta.index is not present. Using meta.indexRefName \n" if($p->opts->verbose);
			my $source = $get->{hits}->{hits}[0]->{_source};
			my $indexRefName = $meta->{indexRefName};
			print "searching for indexRefName:: ".$indexRefName."\n" if($p->opts->verbose);

			my $references = $source->{references};
			if (ref $references eq ref []) {
				foreach my $reference(@$references){
					print 'Current reference:: '.$reference->{name}."\n" if($p->opts->verbose);
					if ($reference->{name} eq $indexRefName) {
						print 'Matched reference:: '.$reference->{name}."\n" if($p->opts->verbose);
						$indexID = $reference->{id};
						last;
					}
				}
			}
	        $index = '.kibana/_doc/index-pattern:'.$indexID;
		} else {
	        $index = '.kibana/doc/index-pattern:'.$indexID;
		}
        print 'Resolved index:: '.$index."\n" if($p->opts->verbose);

        $get = getSearchIndex($p->opts->url, $index);
		$index = $get->{_source}->{'index-pattern'}->{title};

		#if raw_query is already set above, use it. Else read main query from saved search.
		if (not defined $raw_query) {
			if (ref $meta->{query}->{query} eq ref {}) {
				$meta->{query}->{query}->{query_string}->{query} =~ s/"/\\"/g;
				$raw_query = '{ "query_string": { "query": "'.$meta->{query}->{query}->{query_string}->{query}.'" } },';
			} elsif (ref $meta->{query}->{query} eq '') {
				if ($meta->{query}->{query} eq '') {
					$meta->{query}->{query} = "*";
				} else {
					$meta->{query}->{query} =~ s/"/\\"/g;
				}
				$raw_query = '{ "query_string": { "query": "'.$meta->{query}->{query}.'" } },';
			} else {
				$p->plugin_exit(CRITICAL, "Can't parse output");
			}
		}

		# Fetch filters from saved query
		my $raw_bool_clauses = '"filter": [],';
		if (ref $meta->{filter} eq ref []) {
			$raw_bool_clauses = getBooleanClauses($meta->{filter});
		}

		if($p->opts->documents > 0) {
			$query = '{ "size": '.$p->opts->documents.', '.$sort.'"query": { "bool": { '.$raw_bool_clauses.'"must": [ '.$raw_query.' { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
		} else {
			$query = '{ "query": { "bool": { '.$raw_bool_clauses.'"must": [ '.$raw_query.' { "range": { "'.$p->opts->timefield.'": { "gte": "'.$timestamp[1].'", "lte": "'.$timestamp[0].'" } } } ] } } }';
		}
	} else {
		$p->plugin_exit(CRITICAL, "Saved query not found");
	}
}

if($p->opts->documents > 0) {
	$get = getSearch($p->opts->url, $index, $query);
} else {
	$get = getCount($p->opts->url, $index, $query);
}

my $total;
if(defined $get && (ref $get->{hits} eq ref {} || defined $get->{count})) {
	print Dumper($get) if ( $p->opts->verbose );
	if (ref $get->{hits}->{total} eq ref {}) {
		print "ES VERSION 7 Search \n" if($p->opts->verbose);
		$total = $get->{hits}->{total}->{value};
	} elsif (defined $get->{hits}->{total}) {
		print "ES VERSION 6 Search \n" if($p->opts->verbose);
		$total = $get->{hits}->{total};
	} else {
		print "ES Count \n" if($p->opts->verbose);
		$total = $get->{count};
	}
	
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

if(defined $p->opts->oneliner) {
	$Data::Dumper::Indent    = 0;
	$Data::Dumper::Sortkeys  = 1;
	$Data::Dumper::Quotekeys = 1;
	$Data::Dumper::Deparse   = 1;
}

my $exit = '';

if (defined $p->opts->fields && $p->opts->documents>0) {
	$exit .= "\n" if(not defined $p->opts->oneliner);
	foreach my $n (@{$get->{hits}->{hits}}) {
		$exit .= dumpKeys($n->{_source});
	}
	if (defined $p->opts->hidecurly) {
		$exit =~ s#[{}]##g;	
		$exit =~ s/\n//;
		$exit =~ s/\n\n/\n/g;
	}

	$exit =~ s/[\n\r]/ /g if(defined $p->opts->oneliner);
	
	$p->plugin_exit($p->check_threshold(check => $total), $p->opts->name." ".(defined $p->opts->search?$p->opts->search:'').": $total " . $exit);
} elsif ($p->opts->documents > 0) {
	$exit .= "\n";
	foreach my $n (@{$get->{hits}->{hits}}) {
		$exit .= Dumper($n->{_source});
	}
	if (defined $p->opts->hidecurly) {
		$exit =~ s#[{}]##g;	
		$exit =~ s/\n\n/\n/g;
	}
	$exit =~ s/[\n\r]/ /g if(defined $p->opts->oneliner);
	
	$p->plugin_exit($p->check_threshold(check => $total), $p->opts->name." ".(defined $p->opts->search?$p->opts->search:'').": $total ".$exit);
} else { 
	$p->plugin_exit($p->check_threshold(check => $total), $p->opts->name." ".(defined $p->opts->search?$p->opts->search:'').": $total"); 
}

#### Subroutines
sub getSearch {
	my ($url, $index, $body) = @_;
	print 'Search Url: '.$url."\n" if($p->opts->verbose);
	print 'Search Index: '.$index."\n" if($p->opts->verbose);
	print 'Search Query: '.$body."\n" if($p->opts->verbose);

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

sub getCount {
	my ($url, $index, $body) = @_;
	print 'Fetching only count from ES \n' if($p->opts->verbose);
	print 'Search Url: '.$url."\n" if($p->opts->verbose);
	print 'Search Index: '.$index."\n" if($p->opts->verbose);
	print 'Search Query: '.$body."\n" if($p->opts->verbose);

	# UserAgent
	my $ua = LWP::UserAgent->new;
	$ua->agent($PROGNAME."/0.1");
	$ua->timeout($p->opts->timeout);
	# Create a request
	my $req;
	$req = HTTP::Request->new(POST => $url.'/'.$index.'/_count');
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

# Handle filters
sub getBooleanClauses {
	my ($filters) = @_;
	my $raw_filters = '"filter":[ ';
	my $raw_must_not = '"must_not":[ ';
	my $raw_should = '"should":[ ';

	my $filter_delimiter = "";
	my $must_not_delimiter = "";
	my $minimum_should = "";

	foreach my $filterJSON(@$filters) {
		my $filterQueryMeta = $filterJSON->{meta};
		my $isNegativeQuery = $filterQueryMeta->{negate};
		my $queryType = lc $filterQueryMeta->{type};
		my $fieldName = $filterQueryMeta->{key};
		my $filterParams = $filterQueryMeta->{params};

		#Handle range and phrase queries
		my $rawFilterQuery = '';
		if ($queryType eq 'phrase'){
			$rawFilterQuery = '{ "term": { "'.$fieldName.'": "'.$filterParams->{query}.'" } }';
		} elsif ($queryType eq 'phrases') {
			$rawFilterQuery = encode_json($filterJSON->{query});
		} elsif ($queryType eq 'exists') {
			$rawFilterQuery = '{ "exists": '.encode_json($filterJSON->{exists}).' }';
		} elsif ($queryType eq 'range') {
			$rawFilterQuery = '{ "range": { "'.$fieldName.'": '.encode_json($filterParams).' } }';

		} else {
			plugin_exit(CRITICAL, 'UNKNOWN QUERY TYPE'.$queryType);
		}

		# sort filterquery into filter or must_not
		if ($isNegativeQuery) {
			$raw_must_not .= $must_not_delimiter.$rawFilterQuery;
			$must_not_delimiter = ",";
		} else {
			$raw_filters .= $filter_delimiter.$rawFilterQuery;
			$filter_delimiter = ",";
		}
	}
	$raw_filters .= " ],";
	$raw_must_not .= " ],";
	$raw_should .= " ],";

	print 'Raw Boolean Clauses: '.$raw_filters.$raw_should.$minimum_should.$raw_must_not."\n" if($p->opts->verbose);
	return $raw_filters.$raw_must_not;
}

sub getSearchIndex {
	my ($url, $index) = @_;

	# UserAgent
	my $ua = LWP::UserAgent->new;
	$ua->agent($PROGNAME."/0.1");
	$ua->timeout($p->opts->timeout);
	# Create a request
	my $req;
	$req = HTTP::Request->new(GET => $url.'/'.$index);

	# Pass request to the user agent and get a response back
	my $res = $ua->request($req);

	# Check the outcome of the response
	my $json = JSON->new;

	$p->plugin_exit(CRITICAL, $res->message) if ($res->is_success == 0);

	return $json->decode($res->content) if ($res->is_success == 1);

	return undef;
}

sub dumpKeys {
    my $orig = shift;
    my @keys = split(/,/, $p->opts->fields);
    my %new;
    @new{ @keys } = @{ $orig }{ @keys };
        foreach my $key (keys %new)
        {
          $new{$key} = substr($new{$key}, 0, $p->opts->length);
        }
		
    return sprintf(Data::Dumper->new([\%new])->Useqq(1)->Dump, "\n");
}

