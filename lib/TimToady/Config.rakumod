
use TOML;

sub load-config() is export {
    my @dirs = ["/etc/infra-api/", "./resources"];
    for @dirs -> $dir {
        my $conf = $dir.IO.add("config.toml");
        if $conf.f {
            return from-toml $conf.slurp;
        }
    }
    Failure.new('config not found');
}

