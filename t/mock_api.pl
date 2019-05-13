#!/usr/bin/perl
use Mojolicious::Lite;
use Data::Dumper;
use JSON;

my %savedSearches;
$savedSearches{"saved_search_1"}{"index_hash"}  = "d9922a60-449d-11e9-932a-bfe6cbee1330";
$savedSearches{"saved_search_1"}{"index_name"}  = "bla";
$savedSearches{"saved_search_1"}{"hits"}        = 25;
$savedSearches{"saved_search_1"}{"query"}       = "user_agent = Mozilla*";

$savedSearches{"saved_search_2"}{"index_hash"}  = "d9922a60-449d-11e9-932a-bfe6cbee1331";
$savedSearches{"saved_search_2"}{"index_name"}  = "bla";
$savedSearches{"saved_search_2"}{"hits"}        = 12;
$savedSearches{"saved_search_2"}{"query"}       = "user_agent = Mozilla*";

post '/.kibana/_search' => sub {
    my ( $mojo ) = @_;
    my $body = $mojo->req->body;
    my $json = decode_json ($body);
    my $searchTitle = $json->{'query'}->{'bool'}->{'must'}[0]->{'match'}->{"search.title"};
    my $savedSearch = $savedSearches{"$searchTitle"};
    return $mojo->render(
        json =>
            { hits => {hits => [{_source => {search => {kibanaSavedObjectMeta => {searchSourceJSON => '{"index":"' . $savedSearch->{'index_hash'} .'","query":{"query":"' . $savedSearch->{'query'} . '"}}'} }}},]}}
    );
};

get "/.kibana/doc/index-pattern:hash" => sub {
    my ( $mojo ) = @_;
    my $hash = substr($mojo->stash('hash'),1);
    my $savedSearch = findSearchByHash($hash);
    return $mojo->render(
        json => {_source => {'index-pattern' => {title => $savedSearch->{'index_name'}}}}
    );
};

post '/:index_name/_search' => sub {
    my ( $mojo ) = @_;
    my $index_name = $mojo->stash('index_name');
    my $body = $mojo->req->body;
    my $json = decode_json ($body);
    my $query = $json->{'query'}->{'bool'}->{'must'}[0]->{'query_string'}->{"query"};
    my $savedSearch = findSearchByIndexQuery($index_name, $query);
    return $mojo->render(
        json => {hits => {'total' => $savedSearch->{'hits'}}}
    );
};

sub findSearchByHash {
    my ($hash) = @_;
    keys %savedSearches; # reset the internal iterator so a prior each() doesn't affect the loop
    while(my($k, $v) = each %savedSearches) {
        if ($v->{"index_hash"} eq $hash) {
            return $v;
        }
    }
}

sub findSearchByIndexQuery {
    my ($index, $query) = @_;
    keys %savedSearches; # reset the internal iterator so a prior each() doesn't affect the loop
    while(my($k, $v) = each %savedSearches) {
        if ($v->{"index_name"} eq $index && $v->{"query"} eq $query) {
            return $v;
        }
    }
}

# app->secrets(['My very secret passphrase.']);
app->start;
