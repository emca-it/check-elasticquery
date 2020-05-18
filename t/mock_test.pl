use Test::Simple tests => 7;
use IPC::Open3;
use Cwd 'abs_path';
use File::Basename;

my $dirname = dirname(abs_path($0));
my $script = "$dirname/../check_elasticquery_6x.pl";

# Setup of Mock API server
print "Starting mock API server...\n";
my($wtr, $rdr, $err);
use Symbol 'gensym'; $err = gensym;
$mockapi_pid = open3($wtr, $rdr, $err,
                    "$dirname/mock_api.pl", "daemon");
sleep(2);

my $output, $exitcode;

# Test OK
$output = `$script -U 'http://localhost:3000' -S 'saved_search_1' -T 'now:now-30d' -w 35 -c 50`;
$exitcode = $?>>8;

ok ($exitcode == 0);
ok (index($output, "OK") != -1);

# Test Warning
$output = `$script -U 'http://localhost:3000' -S 'saved_search_2' -T 'now:now-30d' -w 20 -c 30`;
$exitcode = $?>>8;

ok ($exitcode == 1);
ok (index($output, "WARNING") != -1);

# Test critical
$output = `$script -U 'http://localhost:3000' -S 'saved_search_2' -T 'now:now-30d' -w 10 -c 20`;
$exitcode = $?>>8;

ok ($exitcode == 2);
ok (index($output, "CRITICAL") != -1);

# verify perfdata format
ok (index($output, "total=25;10;20") != -1);

# shut down the mock API server
kill 'TERM', $mockapi_pid;
