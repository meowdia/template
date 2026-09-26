# SPDX-FileCopyrightText: 2026 Meowdia Community
# SPDX-License-Identifier: MIT OR Apache-2.0

{
  description = "A very basic flake";

  inputs = {
    crane.url = "github:ipetkov/crane";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
  };

  outputs =
    {
      self,
      crane,
      fenix,
      flake-utils,
      nixpkgs,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ fenix.overlays.default ];
        };

        manifest = nixpkgs.lib.fromTOML (builtins.readFile ./Cargo.toml);

        craneLib = (crane.mkLib pkgs).overrideToolchain (
          pkgs.fenix.stable.withComponents [
            "cargo"
            "rustc"
            "rustfmt"
            "clippy"
          ]
        );

        commonArgs = {
          pname = manifest.package.name;
          version = manifest.package.version;
          src = pkgs.lib.fileset.toSource {
            root = ./.;
            fileset = pkgs.lib.fileset.unions [
              (craneLib.fileset.commonCargoSources ./.)
            ];
          };
          strictDeps = true;
        };

        cargoArtifacts = craneLib.buildDepsOnly (
          commonArgs
          // {
            cargoExtraArgs = "--workspace";
          }
        );

        cargoArtifactsDev = cargoArtifacts.overrideAttrs (
          final: prev: {
            CARGO_PROFILE = "dev";
          }
        );

        crateClippy = craneLib.cargoClippy (
          commonArgs
          // {
            CARGO_PROFILE = "dev";
            cargoArtifacts = cargoArtifactsDev;
            cargoClippyExtraArgs = "--all-targets -- --deny warnings";
          }
        );

        crateFmt = craneLib.cargoFmt commonArgs;

        crateTest = craneLib.cargoTest (
          commonArgs
          // {
            CARGO_PROFILE = "dev";
            cargoArtifacts = cargoArtifactsDev;
          }
        );

        crate = craneLib.cargoBuild (
          commonArgs
          // {
            inherit cargoArtifacts;
          }
        );
      in
      {
        checks = {
          inherit crateClippy crateTest crateFmt;
        };

        apps = builtins.listToAttrs (
          map
            (
              name:
              let
                cmd = pkgs.writeShellScript "just-${name}" "${pkgs.just}/bin/just ${name}";
              in
              {
                inherit name;
                value = {
                  type = "app";
                  program = "${cmd}";
                  meta = {
                    description = "runs `just ${name}`";
                  };
                };
              }
            )
            [
              "build"
              "test"
              "lint"
              "check"
              "clean"
              "fmt"
            ]
        );

        packages = {
          ci_clippy = crateClippy;
          ci_test = crateTest;
          ci_fmt = crateFmt;
          deps = cargoArtifacts;
          deps_dev = cargoArtifactsDev;
          default = crate;
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            pkgs.fenix.stable.toolchain
            just
            reuse
          ];
        };
      }
    );
}
