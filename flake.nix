{

  inputs.nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0"; # latest stable

  inputs.reliquary-archiver.url = "git+https://github.com/IceDynamix/reliquary-archiver.git";
  inputs.reliquary-archiver.flake = false;

  inputs.turnbasedgamedata.url = "git+https://gitlab.com/Dimbreath/turnbasedgamedata.git";
  inputs.turnbasedgamedata.flake = false;

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
          wayland.dev # The file `wayland-client.pc` needs to be installed and the PKG_CONFIG_PATH environment variable must contain its parent directory
          cargo
          openssl
          libpcap
          libcap # setcap
          sccache
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
        in
        rec {
          reliquary-archiver-unwrapped = (
            pkgs.callPackage (
              {
                rustPlatform,
                ...
              }:
              rustPlatform.buildRustPackage (finalAttrs: rec {

                pname = "reliquary-archiver-unwrapped";
                name = pname;

                nativeBuildInputs = (native-build-input-packages pkgs);

                # ## build.rs requires internet access, which nix sandbox disallows,
                # ## use "fixed-output derivation", but outputHash ends up changing
                # ## differently every time running
                # outputHashMode = "recursive";
                # outputHash = "";

                cargoLock.lockFile = "${inputs.reliquary-archiver.outPath}/Cargo.lock";
                cargoLock.allowBuiltinFetchGit = true;

                src = (
                  # patch before passing src, else naersk will patch on dummy-src instead
                  pkgs.applyPatches {
                    src = inputs.reliquary-archiver.outPath;
                    patches = [ ./0001-PRE_DOWNLOADED_RESOURCE_DIR.patch ];
                    name = "reliquary-archiver-patched";
                  }
                );

                # env
                PRE_DOWNLOADED_RESOURCE_DIR = inputs.turnbasedgamedata.outPath;
                RUST_BACKTRACE = 1;
                # RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
                # SCCACHE_DIR = "/tmp/.cache/sccache";
                PKG_CONFIG_PATH = (
                  builtins.concatStringsSep ":" (map (pkg: "${pkg}/lib/pkgconfig") nativeBuildInputs)
                );

                # release = false;

                # # nix build doesn't have permission for setcap
                # postInstall = ''
                #   setcap CAP_NET_RAW=+ep $out/bin/reliquary-archiver
                # '';

                meta.mainProgram = "reliquary-archiver";

              })

            ) { }
          );

          reliquary-archiver-capsh = (
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

          default = reliquary-archiver-capsh;

          reliquary-archiver-ro = (
            # bwrap: a "sandbox" that only makes files read-only
            # run0: allow CAP_NET_RAW, then use bwrap to restrict
            # setpriv: run as current user instead of root, use it since:
            # run0 --user --empower: bwrap: Unexpected capabilities but not setuid, old file caps config?
            # bwrap: Specifying --uid requires --unshare-user or --userns
            pkgs.writeShellScriptBin "reliquary-archiver-ro" ''
              set -x
              ${pkgs.systemd}/bin/run0 \
                ${pkgs.bubblewrap}/bin/bwrap --ro-bind / / --dev /dev --clearenv \
                --cap-drop ALL --cap-add CAP_SETUID --cap-add CAP_SETGID --cap-add CAP_NET_RAW \
                --new-session --unshare-pid --unshare-ipc --unshare-uts --share-net --unshare-cgroup-try \
                --tmpfs "$HOME" --tmpfs /tmp --tmpfs /run --ro-bind /run/current-system/sw/bin/ /run/current-system/sw/bin/ \
                -- \
                ${pkgs.util-linux}/bin/setpriv --reuid=$(id -u) --regid=$(id -g) --clear-groups --inh-caps +net_raw --ambient-caps +net_raw -- \
                ${reliquary-archiver-unwrapped}/bin/reliquary-archiver "$@"
            ''
          );

        }
      );

      apps = forEachSupportedSystem (
        { pkgs }: {
          default = {
            type = "app";
            program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/reliquary-archiver";
          };
          ro = {
            type = "app";
            program = "${
              self.packages.${pkgs.stdenv.hostPlatform.system}.reliquary-archiver-ro
            }/bin/reliquary-archiver-ro";
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
          environment.systemPackages = [
            self.packages.${pkgs.stdenv.hostPlatform.system}.reliquary-archiver-ro
          ];
        }
      );

    };
}
