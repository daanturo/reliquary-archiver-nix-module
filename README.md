
Nix packaging for https://github.com/IceDynamix/reliquary-archiver.


# Usage

Assume that Nix Flakes are
[enabled](https://wiki.nixos.org/wiki/Flakes#Enabling_flakes_permanently).

This repository uses Github Actions to build and push binary cache to
[Cachix](https://www.cachix.org/).  Optionally to avoid building locally and
pull pre-built binary(s) instead, you can first configure NixOS to use
substituters in your configuration:

```nix
{

  nix.settings.substituters = [
	# ... others ...
    "https://daanturo.cachix.org?priority=42" # prioritize cache.nixos.org (40) and other cachix (41), use this last
  ];
  nix.settings.trusted-public-keys = [
    # ... others ...
    "daanturo.cachix.org-1:1sWdLYofZ2zEBvCWl2LWvV/jvPREWc3Gx70jEy1rpBA="
  ];

}
```

## dev shell

This flake provides a `nix`
[develop](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-develop.html)
shell for building `reliquary-archiver` on NixOS.

## Standalone command

To run `reliquary-archiver` without installing (but without configured binary
cache as mentioned above, building still happens locally, of course):

```sh
nix run "git+https://github.com/daanturo/reliquary-archiver-nix-module.git" -- --help
```

For this command, privilege escalation will ask for root permission.  Because
the
[operation](https://github.com/IceDynamix/reliquary-archiver#pcap-instructions)
`sudo setcap CAP_NET_RAW=+ep target/release/reliquary-archiver` cannot be done
with `nix build`, `capsh` with root permission is used as a workaround to
temporarily allow packet capturing.


To force latest version of upstream `reliquary-archiver`:
```sh
git clone https://github.com/daanturo/reliquary-archiver-nix-module
cd reliquary-archiver-nix-module
git pull --rebase # optional
nix flake update --commit-lock-file
nix run . -- --help
```

<!-- Alternatively, use the potentially deprecating option `--update-input`: -->
<!-- ```sh -->
<!-- nix run "git+https://github.com/daanturo/reliquary-archiver-nix-module.git" --update-input reliquary-archiver --update-input turnbasedgamedata -- --help -->
<!-- ``` -->

## Declarative configuration

In your
[system](https://wiki.nixos.org/wiki/NixOS_system_configuration#Defining_NixOS_as_a_flake)'s
`flake.nix`:

```nix
{

  # ...other inputs, including "nixpkgs"...

  inputs.reliquary-archiver-nix-module.url = "git+https://github.com/daanturo/reliquary-archiver-nix-module.git";
  # inputs.reliquary-archiver-nix-module.inputs.nixpkgs.follows = "nixpkgs";  # optional to reduce inputs size, but do not use this line if you configure cachix as it's extremely likely to cause cache misses

  outputs = (
    inputs@{ self, ... }:
    {
      # ...other outputs...
      nixosConfigurations = {
        "hostname" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ inputs.reliquary-archiver-nix-module.nixosModules.default ];
        };
      };
    }
  );

}
```

Binary will be available at `/run/wrappers/bin/reliquary-archiver` (added to
PATH by default on NixOS).


## read-only version

Version bounded by a pseudo-sandbox:

```sh
# one-time execution
nix run "git+https://github.com/daanturo/reliquary-archiver-nix-module.git"#ro -- --help
# persist to nix profile
nix profile add "git+https://github.com/daanturo/reliquary-archiver-nix-module.git"#reliquary-archiver-ro
```

By using `bwrap`, normally, the above won't be able to write to any files, nor
read from any such as .pcap files, hence as of 2026-07, is only useful for
`--stream` mode.  While attempting to lessen the damage of attacks such as
supply-chain & MITM, it DOES NOT guarantee full protection against them.  See
[flake.nix](./flake.nix)`/reliquary-archiver-ro` for the implementation.
