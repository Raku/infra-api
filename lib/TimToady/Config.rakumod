use TOML;

sub load-config() is export {
    my IO() @dirs = "/etc/infra-api/", "./resources";

    for @dirs.map(*.add: "config.toml") -> $conf {
        if $conf.f {
            return from-toml $conf.slurp;
        }
    }

    fail "Config file does not exist, directories checked: {@dirs.gist}";
}
