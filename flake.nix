{
  description = "RobustMQ - A high-performance distributed message queue built with Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, rust-overlay, ... }:
    let
      system = "x86_64-linux";
      overlays = [ (import rust-overlay) ];
      pkgs = import nixpkgs {
        inherit system overlays;
      };
      version =
        let
          cargoToml = builtins.readFile ./Cargo.toml;
          versionLine = builtins.head (
            builtins.filter (line: builtins.match "^version = \".*\"$" line != null) (
              pkgs.lib.splitString "\n" cargoToml
            )
          );
        in
        builtins.substring 10 (builtins.stringLength versionLine - 11) versionLine;
    in
    {
      packages.x86_64-linux = {
        default = pkgs.rustPlatform.buildRustPackage {
          pname = "robustmq-server";
          inherit version;

          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
            allowBuiltinFetchGit = true;
          };

          nativeBuildInputs = with pkgs; [
            rust-bin.stable.latest.default
            cargo
            pkg-config
            llvmPackages.clang
            llvmPackages.libclang
            libtool
            cmake
            protobuf
          ];

          buildInputs = with pkgs; [
            openssl
            zlib
            sqlite
            rdkafka
            cyrus_sasl
            lz4
            zstd
          ];

          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";

          # Environment variables for rdkafka-sys build
          RDKAFKA_SYS_WANT_STATIC = "1";

          # Ensure autotools are available
          preBuild = ''
            export PATH="${pkgs.autoconf}/bin:${pkgs.automake}/bin:${pkgs.libtool}/bin:$PATH"
          '';

          RUST_BACKTRACE = "1";

          cargoBuildFlags = [
            "--package"
            "cmd"
            "--bin"
            "broker-server"
          ];

          doCheck = false;

          installPhase = ''
            mkdir -p $out/bin
            cp target/release/* $out/bin/
          '';

          meta = with pkgs.lib; {
            description = "RobustMQ Server - High-performance distributed message queue";
            homepage = "https://github.com/robustmq/robustmq";
            license = licenses.asl20;
            platforms = platforms.unix;
          };
        };
      };
    };
}
