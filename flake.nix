{

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # latest stable

    naersk.url = "github:nix-community/naersk";
    naersk.inputs.nixpkgs.follows = "nixpkgs";

    reliquary-archiver.url = "git+https://github.com/IceDynamix/reliquary-archiver.git";
    reliquary-archiver.flake = false;

    turnbasedgamedata.url = "git+https://gitlab.com/Dimbreath/turnbasedgamedata.git";
    turnbasedgamedata.flake = false;

  };

  # nixConfig.sandbox = "relaxed"; # cannot set as untrusted user anyway

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forEachSupportedSystem =
        f:
        nixpkgs.lib.genAttrs supportedSystems (
          system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              overlays = [ ];
            };
          }
        );

      native-build-input-packages = (
        pkgs:
        (with pkgs; [
          pkg-config
          wayland
          cargo
          openssl
          libpcap
          libcap # setcap
        ])
      );

    in
    {

      devShells = forEachSupportedSystem (
        { pkgs }: {
          default = pkgs.mkShell {
            packages = (native-build-input-packages pkgs);
          };
        }
      );

      packages = forEachSupportedSystem (
        { pkgs }:
        let
          naersk' = pkgs.callPackage inputs.naersk { };
        in
        {
          default = (

            # pkgs.stdenv.mkDerivation
            naersk'.buildPackage (rec {
              pname = "reliquary-archiver";

              src = (
                # patch before passing src, else naersk will patch on dummy-src instead
                pkgs.applyPatches {
                  src = inputs.reliquary-archiver.outPath;
                  patches = [ ./0001-PRE_DOWNLOADED_RESOURCE_DIR.patch ];
                  name = "reliquary-archiver-patched";
                }
              );
              PRE_DOWNLOADED_RESOURCE_DIR = inputs.turnbasedgamedata.outPath;

              # ## build.rs requires internet access, which nix sandbox disallows,
              # ## use "fixed-output derivation", but outputHash ends up changing
              # ## differently every time running
              # outputHashMode = "recursive";
              # outputHashAlgo = "sha256";
              # outputHash = "";

              nativeBuildInputs = (native-build-input-packages pkgs);

              RUST_BACKTRACE = 1;
              # release = false;

              # # nix build doesn't have permission for setcap
              # postInstall = ''
              #   setcap CAP_NET_RAW=+ep $out/bin/reliquary-archiver
              # '';

            })

          );
        }
      );

      nixosModules.default = (
        { config, pkgs, ... }: {
          security.wrappers."reliquary-archiver" = {
            source = "${self.packages.${pkgs.system}.default}/bin/reliquary-archiver";
            capabilities = "cap_net_raw+ep";
            owner = "root";
            group = "root";
          };
        }
      );

    };
}
