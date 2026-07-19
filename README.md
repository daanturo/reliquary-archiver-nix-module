
Nix packaging for https://github.com/IceDynamix/reliquary-archiver.


# Usage

Assume that Nix Flakes are [enabled](https://wiki.nixos.org/wiki/Flakes#Enabling_flakes_permanently).

## dev shell

This flake provides a `nix`
[develop](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-develop.html)
shell for building `reliquary-archiver` on NixOS.

## Standalone command

To run `reliquary-archiver` without installing (but building still happens
locally, of course):

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

## flake.nix

In your [system](https://wiki.nixos.org/wiki/NixOS_system_configuration#Defining_NixOS_as_a_flake)'s `flake.nix`:
```nix
{

  # ...other inputs, including "nixpkgs"...

  inputs.reliquary-archiver-nix-module.url = "git+https://github.com/daanturo/reliquary-archiver-nix-module.git";
  inputs.reliquary-archiver-nix-module.inputs.nixpkgs.follows = "nixpkgs";

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

Binary will be available at `/run/wrappers/bin/reliquary-archiver` (added to PATH by default on NixOS).
