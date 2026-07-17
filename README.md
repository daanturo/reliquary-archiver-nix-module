
Nix packaging for https://github.com/IceDynamix/reliquary-archiver.


# Usage

Assume that Nix Flakes are [enabled](https://wiki.nixos.org/wiki/Flakes#Enabling_flakes_permanently):

## flake.nix

In your [system](https://wiki.nixos.org/wiki/NixOS_system_configuration#Defining_NixOS_as_a_flake)'s `flake.nix`:
```nix
{

  # ...other inputs, including "nixpkgs"...

  inputs.reliquary-archiver-nix.url = "git+https://github.com/daanturo/reliquary-archiver-nix-module.git";
  inputs.reliquary-archiver-nix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = (
    inputs@{ self, ... }:
    {
      # ...other outputs...
      nixosConfigurations = {
        "hostname" = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [ inputs.reliquary-archiver-nix.nixosModules.default ];
        };
      };
    }
  );
  
}
```

## Standalone command

```sh
# '--recreate-lock-file --update-input': for grabbing the latest git version from https://github.com/IceDynamix/reliquary-archiver
cp $(nix build "git+https://github.com/daanturo/reliquary-archiver-nix-module.git"#default --no-link --print-out-paths --recreate-lock-file --update-input nixpkgs --update-input reliquary-archiver --update-input turnbasedgamedata)/bin/reliquary-archiver ./reliquary-archiver
sudo setcap CAP_NET_RAW=+ep ./reliquary-archiver
```

(Ideally, it should just be:
```sh
nix shell "git+https://github.com/daanturo/reliquary-archiver-nix-module.git"#default -c reliquary-archiver -s
```

But since `setcap` is impossible at the `nix build` step (as of 2026-07), the above 1-line command can't be achieved.)
