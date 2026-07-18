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
        rec {
          reliquary-archiver-unwrapped = (

            naersk'.buildPackage (rec {

              meta.mainProgram = "reliquary-archiver";

              pname = "reliquary-archiver-unwrapped";

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

          reliquary-archiver-wrapped = (
            pkgs.writeShellScriptBin "reliquary-archiver" ''
              if [ "$EUID" -eq 0 ]; then
                echo "Don't run this as root directly" >>/dev/stderr
                exit 1
              fi

              set -x

              exec ${pkgs.systemd}/bin/run0 ${pkgs.libcap}/bin/capsh \
                --user="$USER" \
                --caps="cap_net_raw+epi" \
                --addamb="cap_net_raw" \
                -- -c "exec ${reliquary-archiver-unwrapped}/bin/reliquary-archiver \"$@\" "
            ''
          );

          default = reliquary-archiver-wrapped;

        }
      );

      apps = forEachSupportedSystem (
        { pkgs }: {
          default = {
            type = "app";
            program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/reliquary-archiver";
          };
        }
      );

      nixosModules.default = (
        { config, pkgs, ... }: {
          security.wrappers."reliquary-archiver" = {
            source = "${
              self.packages.${pkgs.stdenv.hostPlatform.system}.reliquary-archiver-unwrapped
            }/bin/reliquary-archiver";
            capabilities = "cap_net_raw+ep";
            owner = "root";
            group = "root";
          };
        }
      );

    };
}
