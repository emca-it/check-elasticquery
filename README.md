# check-elasticquery
This plugin check Elasticsearch query total documents. It is aimed to work with Energy Logserver, OP5 Log Analytics and is supposed to work with opensource Elasticsearch and x-pack.

**Usage examples**

Total documents in  'beats*' index for latest 24 hours. Latest 24 hours is default time range.

`./check_elasticquery.pl -U 'http://user:password@localhost:9200' -i 'beats*'`

Execute saved search named *protection* for latest 15 minutes. By default it checks *@timestamp* field, you can change it in *timefield* option.

`./check_elasticquery.pl -U 'http://user:password@localhost:9200' -i 'beats*' -S 'protection' -T 'now:now-15m'`

As above plus show one document. One doesn't mean latest. For latest you should execute json query with defined sort by time.

`./check_elasticquery.pl -U 'http://user:password@localhost:9200' -i 'beats*' -S 'protection' -T 'now:now-15m' -D 1`

Execute json query. Time range option wouldn't work. You should define time range in query.

`./check_elasticquery.pl -U 'http://user:password@localhost:9200' -i 'beats*' -q '
{
 "size": 0,
 "query": {
    "bool": {
      "must": [
        {
          "query_string": {
            "query": "task:\"Special Logon\"",
            "analyze_wildcard": true,
            "default_field": "*"
          }
        },
        {
          "range": {
            "@timestamp": {
              "gte": "now-1d/d",
              "lte": "now/d"
            }
          }
        }
      ]
    }
  }
}
'`
