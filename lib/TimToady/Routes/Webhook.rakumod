use Digest::HMAC;
use Digest::SHA2;
use Cro::HTTP::Router;

#| webhook-routes holds all webhook routes.
sub webhook-routes(:$config, :$pool) is export {
    route {
        before-matched {
            # Validate payload from GitHub.
            request-body-blob -> $body {
                # NOTE: Maybe we should switch to a faster implementation of hmac.
                with request.headers.grep(*.name eq 'X-Hub-Signature-256')[0].value -> $github-sig {
                    my Str $hmac-sig = "sha256=%s".sprintf: hmac-hex(
                                           $config<raku-doc><secret-token>, $body, &sha256
                                       );
                    # NOTE: Timing safe comparision should be made.
                    forbidden unless $github-sig eq $hmac-sig;
                } else {
                    response.status = 400;
                    content 'text/plain', 'Must include X-Hub-Signature-256.';
                }
                request.set-body($body);
            }
        }

        # Early response on ping event, no response on any event other than
        # 'push'.
        before-matched {
            given request.headers.grep(*.name eq 'X-GitHub-Event')[0].value {
                when 'ping' { content 'text/plain', 'pong'; }
                when 'push' { }
                default {
                    request.status = 501;
                    content 'text/plain', 'Cannot handle this event: {$_.gist}.';
                }
            }
        }

        post -> 'raku-doc', :%headers is header {
            request-body-text -> $event {
                my $dbh = $pool.get-connection();
                LEAVE .dispose with $dbh;

                # Insert a task on push.
                my $sth = $dbh.execute(
                    'INSERT INTO task (type, detail) VALUES (?, ?) RETURNING id;',
                    'raku-doc-push', $event
                );

                content 'text/plain', $sth.row(:hash)<id>;
            }
        }
    }
}
