use TOML;
use JSON::Fast;
use Pg::Notify;
use DBIish::Pool;

constant $running-env = "$*HOME/.timtoady-taskrunner-pid";

#| TimToady::TaskRunner is a taskrunner made specifically for Raku Doc build
#| tasks.
sub MAIN() is export {
    my &formatted-time = { DateTime.now.utc.truncated-to('minute') };

    # If running instance is detected, quit.
    if $running-env.IO.f {
        my Str $running-pid = $running-env.IO.slurp;
        my Proc $proc = run «ps -p "$running-pid"», :out;
        sink $proc.out.slurp(:close);

        if $proc.exitcode == 0 {
            put "{formatted-time()} Quit. Running instance detected...";
            exit;
        }
    }
    # Write pid to $running-env file.
    $running-env.IO.spurt($*PID);

    my IO $timtoady-config = 'resources/config.toml'.IO;
    die "Config file does not exist: {$timtoady-config.absolute}" unless $timtoady-config.f;
    die "log directory doesn't exist." unless '.logs'.IO.d;

    my $config = from-toml $timtoady-config.slurp;
    my $pool = DBIish::Pool.new(
        driver => 'Pg',
        |%(
            host => $config<db-host>,
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
                put "{formatted-time()} [{%task<id>}]: Started";
                run-task(%task, :$dbh, :$config);
                put "{formatted-time()} [{%task<id>}]: Completed";
            }
            $tasks ⚛= $dbh.execute("SELECT COUNT(id) FROM task WHERE status = 'todo';").row(:hash)<count>;
        }

        # sleep for some time before checking $tasks again.
        sleep 30;
    }
}

multi sub run-task(%task, :$dbh, :$config) {
    my $log-file = '.logs'.IO.add(%task<id> ~ '.txt');

    # Output will be saved to this log file.
    my $handle = open :x, $log-file;
    LEAVE .close with $handle;

    my $proc;
    my %event = from-json %task<detail>;

    given %task<type> {
        when 'raku-doc-push' {
            $proc = Proc::Async.new("scripts/01-raku-doc-latest.bash", %event<after>);
        }
        default {
            die "[{%task<id type>.gist}]: Cannot handle this type of task.";
        }
    }

    # Bind output.
    $proc.bind-stdout($handle);
    $proc.bind-stderr($handle);

    my $promise = $proc.start;

    with await $proc.pid -> Int $pid {
        $dbh.execute(
            "UPDATE task SET status = 'in-progress', started = now(), pid = ? WHERE id = ?;",
            $pid, %task<id>
        );
    }

    sink try await $promise;

    CATCH {
        $dbh.execute(
            'UPDATE task SET completed = now(), status = ?, pid = NULL WHERE id = ?;',
            "failed", %task<id>
        );
        put "[{%task<id>}]: Kill it! :: {$_}";
        $proc.kill: SIGKILL
    }
}
