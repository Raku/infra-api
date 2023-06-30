use Digest::HMAC;
use Digest::SHA2;
use Cro::HTTP::Router;

use TimToady::Session;
use TimToady::Routes::Webhook;

#| routes holds all routes for the project.
sub routes(:$config, :$pool) is export {
    route {
        get -> 'ping' {
            content 'text/plain', 'pong';
        }

        # No auth
        include 'webhook' => webhook-routes(:$config, :$pool);
        
        # Auth
    }
}
