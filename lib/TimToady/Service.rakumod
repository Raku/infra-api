use TOML;
use Cro::HTTP::Router;
use Cro::HTTP::Server;

#| Tim Toady is a simple program to run CI pipelines.
sub MAIN() is export {
    my IO $timtoady-config = 'resources/config.toml'.IO;
    die "Config file does not exist: {$timtoady-config.absolute}" unless $timtoady-config.f;

    my $config = from-toml($timtoady-config.slurp);

    my $application = route {
        get -> 'ping' {
            content 'text/plain', 'pong';
        }

        post -> 'project', $name, $webhook-event {
            my $event-config = $config<project>{$name}{$webhook-event};
            not-found without $event-config;

            request-body 'application/json' => -> %event {
                ...
            }
        }
    }

    my Cro::Service $http = Cro::HTTP::Server.new(
        http => <1.1>,
        host => $config<host>,
        port => $config<port>,
        :$application,
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
            say "Shutting down...";
            $http.stop;
            done;
        }
    }
}
