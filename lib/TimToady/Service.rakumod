use TOML;
use Cro::HTTP::Router;
use Cro::HTTP::Server;
use Template::Nest::Fast;

#| Tim Toady is a simple program to run CI pipelines.
sub MAIN() is export {
    my IO $timtoady-config = 'resources/config.toml'.IO;
    die "Config file does not exist: {$timtoady-config.absolute}" unless $timtoady-config.f;

    my IO $template-dir = 'templates'.IO;
    die "Template directory does not exist: {$template-dir.absolute}" unless $template-dir.d;

    my $config = from-toml $timtoady-config.slurp;
    my $nest = Template::Nest::Fast.new: :$template-dir;

    # %pages holds all the page templates.
    my %pages = %(
        # index returns a list of all projects.
        index => %(
            TEMPLATE => 'index',
            name => $config<name>,
            description => $config<description>,
            body => %(
                TEMPLATE => 'project-list',
                # table of all projects with name, description.
                items => [|$config<project>.keys.map: {
                    %(
                        TEMPLATE => 'project-list-item',
                        name => $config<project>{$_}<name>,
                        description => $config<project>{$_}<description>,
                    )
                }]
            )
        )
    );

    # $application holds all the routes.
    my $application = route {
        get -> 'ping' {
            content 'text/plain', 'pong';
        }

        #| index returns a list of all projects.
        get -> {
            content 'text/html', $nest.render(%pages<index>);
        }

        #| listen for POST requests for defined events.
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
