# check-elasticquery
This plugin check Elasticsearch query total documents. It is aimed to work with Energy Logserver, OP5 Log Analytics and is supposed to work with opensource Elasticsearch and x-pack.

**Dependencies for Centos 7:**

`# yum install perl-Monitoring-Plugin perl-libwww-perl perl-LWP-Protocol-https perl-JSON perl-String-Escape`

**Usage**
```
$ ./check_elasticquery.pl -U|--url=<url> -i|--index=<index> 
    [ -q|--query=<json query> ]
    [ -S|--search=<saved search> ]
    [ -T|--timerange=<lte:gte> ]
    [--timefield=<time field> ]
    [ -c|--critical=<critical threshold> ] 
    [ -w|--warning=<warning threshold> ]
    [ -t <timeout>]
    [ -v|--verbose ]
```

**Usage examples**

Total documents in  'beats*' index for latest 24 hours. Latest 24 hours is default time range.

`./check_elasticquery.pl -U 'http://user:password@localhost:9200' -i 'beats*'`

Execute saved search named *protection* for latest 15 minutes. By default it checks *@timestamp* field, you can change it in *--timefield* option.

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

Date match format for timerange option:
https://www.elastic.co/guide/en/elasticsearch/reference/current/common-options.html#date-math

**Timerange examples:**

`-T 'now/h:now-1h/h'` - events from latest hour rounded to 0 minute. When you check at 15:50 then it check 14:00-15:00.

`-T 'now:now-1h'` - events from latest hour.  When you check at 15:50 then it check 14:50-15:50.

`-T 'now:now-1h'` - events from latest hour.  When you check at 15:50 then it check 14:50-15:50.

`-T '1540482600:1540479000'` - events in defined time range.

Default is `'now/now-1d'` - events from latest 24 hours (1 day).
