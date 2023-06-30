use TOML;
use DBIish::Pool;
use Cro::HTTP::Server;
use Template::Nest::Fast;

use TimToady::Config;
use TimToady::Routes;

#| Tim Toady is a simple program to run Raku Infra CI pipelines.
sub MAIN() is export {

    my IO $template-dir = 'templates'.IO;
    die "Template directory does not exist: {$template-dir.absolute}" unless $template-dir.d;

    my $config = load-config;
    my $nest = Template::Nest::Fast.new: :$template-dir;
    my $pool = DBIish::Pool.new(
        driver => 'Pg',
        |%(
            host => $config<db-host>,
            database => $config<db-name>,
            user => $config<db-user>,
            password => $config<db-pass>,
        )
    );

    my Cro::Service $http = Cro::HTTP::Server.new(
        http => <1.1>,
        host => $config<host>,
        port => $config<port>,
        application => routes(:$config, :$pool),
        :allowed-methods<GET POST>,
        body-parsers => [
                         # Don't parse any kind of body except a JSON one; anything else
                         # will throw an exception when `.body` is called.
                         Cro::HTTP::BodyParser::JSON
                     ]
    );
    $http.start;

    put "Listening at http://{$config<host>}:{$config<port>}";
    react {
        whenever signal(SIGINT) {
            put "Shutting down...";
            $http.stop;
            done;
        }
    }
}
