use Digest::HMAC;
use Digest::SHA2;
use Cro::HTTP::Router;

#| webhook-routes holds all webhook routes.
sub webhook-routes(:$config) is export {
    my Str $raku-doc-secret = $config<raku-doc><secret-token>;

    route {
        before-matched {
            # Validate payload from GitHub.
            request-body-blob -> $body {
                # NOTE: Maybe we should switch to a faster implementation of hmac.
                my Str $github-sig = request.headers.grep(*.name eq 'X-Hub-Signature-256')[0].value;
                my Str $hmac-sig = "sha256=%s".sprintf: hmac-hex($raku-doc-secret, $body, &sha256);
                forbidden unless $github-sig eq $hmac-sig;
            }

            # Early response on ping event.
            if request.headers.grep(*.name eq 'X-GitHub-Event')[0].value eq 'ping' {
                content 'text/plain', 'pong';
            }
        }

        post -> 'raku-doc', :%headers is header {
            request-body 'application/json' => -> %event {
                content 'text/plain', 'ok';
            }
        }
    }
}
