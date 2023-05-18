use TOML;
use JSON::Fast;
use Pg::Notify;
use DBIish::Pool;

constant $running-env = "$*HOME/.timtoady-taskrunner-pid";

#| TimToady::TaskRunner is a taskrunner made specifically for Raku Doc build
#| tasks.
sub MAIN() is export {
    # If running instance is detected, quit.
    if $running-env.IO.f {
        my Str $running-pid = $running-env.IO.slurp;
        my Proc $proc = run «ps -p "$running-pid"», :out;
        sink $proc.out.slurp(:close);

        if $proc.exitcode == 0 {
            put "{DateTime.now} Quit. Running instance detected...";
            exit;
        }
    }
    # Write pid to $running-env file.
    $running-env.IO.spurt($*PID);

    my IO $timtoady-config = 'resources/config.toml'.IO;
    die "Config file does not exist: {$timtoady-config.absolute}" unless $timtoady-config.f;

    my $config = from-toml $timtoady-config.slurp;
    my $pool = DBIish::Pool.new(
        driver => 'Pg',
        |%(
            database => $config<db-name>,
            user => $config<db-user>,
            password => $config<db-pass>,
        )
    );

    my atomicint $tasks = 0;
    {
        my $dbh = $pool.get-connection();
        LEAVE .dispose with $dbh;

        $tasks ⚛= $dbh.execute("SELECT COUNT(id) FROM task WHERE status = 'todo';").row(:hash)<count>;
        put "Todo tasks: {$tasks}";

        # Fetch in-progress tasks. If they're running then they must be killed.
        my $sth = $dbh.execute("SELECT id, pid FROM task WHERE status = 'in-progress';");
        put "In-progress tasks: {$sth.allrows(:array-of-hash).gist}";
    }

    start {
        my $dbh = $pool.get-connection();
        LEAVE .dispose with $dbh;

        my $notify = Pg::Notify.new(db => $dbh, channel => 'task_insert');
        react {
            whenever $notify -> $notification {
                $tasks⚛++;
            }
        }
    }

    loop {
        while ⚛$tasks > 0 {
            my $dbh = $pool.get-connection();
            LEAVE .dispose with $dbh;

            my $sth = $dbh.execute(
                "SELECT id, detail, type
                 FROM task
                 WHERE status = 'todo'
                 ORDER BY created
                 LIMIT 1
                 FOR UPDATE SKIP LOCKED;"
            );
            with $sth.row(:hash) -> %task {
                put "{DateTime.now} Starting task: {%task<id type>.gist}";
                run-task(%task<type>, %task, :$dbh, :$config);
                put "{DateTime.now} Completed task: {%task<id type>.gist}";
            }
            $tasks ⚛= $dbh.execute("SELECT COUNT(id) FROM task WHERE status = 'todo';").row(:hash)<count>;
        }
    }
}

multi sub run-task('raku-doc-push', %task, :$dbh, :$config) {
    my $log-file = $config<webroot>.IO.add(%task<id> ~ '.txt');

    my $action-handle = open :x, $log-file;
    LEAVE .close with $action-handle;

    my $output-dir = "/var/www/unfla.me.neon.raku-doc-builds/".IO.add(%task<id>);
    mkdir $output-dir, 0o755;

    my %event = from-json %task<detail>;
    my $action-proc = Proc::Async.new(
        "scripts/10-raku-doc-latest.raku", %event<after>, $output-dir.absolute
    );
    $action-proc.bind-stdout($action-handle);
    $action-proc.bind-stderr($action-handle);

    react {
        whenever $action-proc.ready {
            $dbh.execute(
                "UPDATE task SET status = 'in-progress', started = now(), pid = ? WHERE id = ?;",
                $_, %task<id>
            );
        }
        whenever $action-proc.start {
            $dbh.execute(
                'UPDATE task SET completed = now(), status = ? WHERE id = ?',
                (.exitcode == 0 ?? 'done' !! 'failed'), %task<id>
            );
            done # gracefully jump from the react block
        }
        whenever signal(SIGTERM).merge: signal(SIGINT) {
            die "Received SIGTERM/SIGINT...";
        }
    }

    CATCH {
        put $_.raku;
        $dbh.execute(
            'UPDATE task SET completed = now(), status = ?, pid = NULL WHERE id = ?;',
            "failed", %task<id>
        );
        put "[Task: {%task<id>}] Kill it!";
        $action-proc.kill: SIGKILL
    }
}
