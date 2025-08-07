{
  description = "RobustMQ - A high-performance distributed message queue built with Rust";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixpkgs, flake-utils, rust-overlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs {
          inherit system overlays;
        };

        # Get version from Cargo.toml
        version = 
          let
            cargoToml = builtins.readFile ./Cargo.toml;
            versionLine = builtins.head (builtins.filter 
              (line: builtins.match "^version = \".*\"$" line != null)
              (pkgs.lib.splitString "\n" cargoToml)
            );
          in
            builtins.substring 10 (builtins.stringLength versionLine - 11) versionLine;

        # Rust toolchain based on rust-toolchain.toml
        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          extensions = [ "rust-src" "rustfmt" "rust-analyzer" ];
        };

        # Common dependencies for building
        buildInputs = with pkgs; [
          pkg-config
          openssl
          zlib
          sqlite
          protobuf
          cmake
          llvmPackages.libclang
          llvmPackages.clang
        ] ++ lib.optionals stdenv.isDarwin [
          darwin.apple_sdk.frameworks.Security
          darwin.apple_sdk.frameworks.CoreFoundation
          darwin.apple_sdk.frameworks.SystemConfiguration
        ];

        nativeBuildInputs = with pkgs; [
          rustToolchain
          cargo
          pkg-config
          protobuf
          cmake
        ];

        # Environment variables for building
        buildEnv = {
          LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
          BINDGEN_EXTRA_CLANG_ARGS = "-I${pkgs.glibc.dev}/include";
          PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.sqlite.dev}/lib/pkgconfig";
          OPENSSL_DIR = "${pkgs.openssl.dev}";
          OPENSSL_LIB_DIR = "${pkgs.openssl.out}/lib";
          OPENSSL_INCLUDE_DIR = "${pkgs.openssl.dev}/include";
          PROTOC = "${pkgs.protobuf}/bin/protoc";
          ROCKSDB_LIB_DIR = "${pkgs.rocksdb}/lib";
        };

        # Build server component
        robustmq-server = pkgs.rustPlatform.buildRustPackage rec {
          pname = "robustmq-server";
          inherit version;

          src = ./.;

          cargoLock = {
            lockFile = ./Cargo.lock;
            allowBuiltinFetchGit = true;
          };

          inherit nativeBuildInputs buildInputs;

          # Apply build environment
          env = buildEnv;

          # Build only server binaries
          cargoBuildFlags = [
            "--package" "cmd"
            "--bin" "broker-server"
          ];

          cargoTestFlags = [
            "--workspace"
            "--exclude" "robustmq-test"
          ];

          # Skip tests in build to avoid issues
          doCheck = false;

          # Install phase
          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/libs $out/config $out/docs

            # Copy main binaries
            cp target/release/broker-server $out/libs/

            # Build additional binaries
            cargo build --release --package cli-command --bin cli-command
            cargo build --release --package cli-bench --bin cli-bench
            
            cp target/release/cli-command $out/libs/ || echo "cli-command not found"
            cp target/release/cli-bench $out/libs/ || echo "cli-bench not found"

            # Copy shell scripts from bin/ directory if exists
            if [ -d "${src}/bin" ]; then
              cp -r ${src}/bin/* $out/bin/
              chmod +x $out/bin/*
            fi

            # Copy config files
            if [ -d "${src}/config" ]; then
              cp -r ${src}/config/* $out/config/
            fi

            # Create version file
            echo "${version}" > $out/config/version.txt

            # Set executable permissions
            chmod +x $out/libs/*

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "RobustMQ Server - High-performance distributed message queue";
            homepage = "https://github.com/robustmq/robustmq";
            license = licenses.asl20;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Build operator component (Go)
        robustmq-operator = pkgs.buildGoModule rec {
          pname = "robustmq-operator";
          inherit version;

          src = ./operator;

          vendorHash = null; # Will be determined automatically

          # Go build flags similar to build.sh
          ldflags = [
            "-s"
            "-w" 
            "-X main.version=${version}"
            "-X main.buildDate=1970-01-01_00:00:00"
          ];

          # Build the operator binary
          buildPhase = ''
            runHook preBuild
            go build -ldflags="${builtins.concatStringsSep " " ldflags}" -o robustmq-operator .
            runHook postBuild
          '';

          # Install phase
          installPhase = ''
            runHook preInstall

            mkdir -p $out/bin $out/config $out/manifests $out/docs

            # Copy binary
            cp robustmq-operator $out/bin/

            # Copy manifest files
            if [ -f robustmq.yaml ]; then
              cp robustmq.yaml $out/manifests/
            fi
            if [ -f sample-robustmq.yaml ]; then
              cp sample-robustmq.yaml $out/manifests/
            fi

            # Copy documentation
            if [ -f README.md ]; then
              cp README.md $out/docs/
            fi

            # Create version file
            echo "${version}" > $out/config/version.txt

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "RobustMQ Kubernetes Operator";
            homepage = "https://github.com/robustmq/robustmq";
            license = licenses.asl20;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Documentation build
        robustmq-docs = pkgs.stdenv.mkDerivation {
          pname = "robustmq-docs";
          inherit version;

          src = ./.;

          nativeBuildInputs = with pkgs; [
            nodejs_20
            nodePackages.npm
          ];

          buildPhase = ''
            runHook preBuild

            # Install dependencies
            npm install

            # Build docs
            npm run docs:build

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out
            cp -r docs/.vitepress/dist/* $out/

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "RobustMQ Documentation";
            homepage = "https://github.com/robustmq/robustmq";
            license = licenses.asl20;
          };
        };

        # Combined package with both server and operator
        robustmq-all = pkgs.symlinkJoin {
          name = "robustmq-${version}";
          paths = [ robustmq-server robustmq-operator ];
          
          postBuild = ''
            mkdir -p $out/package-info
            cat > $out/package-info/build-info.txt << EOF
Package: robustmq-all
Version: ${version}
Build Date: 1970-01-01 00:00:00 UTC
Components: server, operator
Built with: Nix Flakes
EOF
          '';

          meta = with pkgs.lib; {
            description = "RobustMQ Complete Package (Server + Operator)";
            homepage = "https://github.com/robustmq/robustmq";
            license = licenses.asl20;
            maintainers = [ ];
            platforms = platforms.unix;
          };
        };

        # Development shell
        devShell = pkgs.mkShell {
          name = "robustmq-dev-shell";
          
          inherit nativeBuildInputs buildInputs;
          
          # Add additional development tools
          packages = with pkgs; [
            # Rust tools
            rustfmt
            clippy
            cargo-watch
            cargo-edit
            cargo-audit
            
            # Go tools (for operator)
            go_1_21
            gopls
            
            # Node.js tools (for docs)
            nodejs_20
            nodePackages.npm
            
            # Additional tools
            git
            curl
            jq
            yq
            
            # Database tools
            sqlite
            
            # Kubernetes tools
            kubectl
            kind
            
            # Build tools
            gnumake
            protobuf
            protoc-gen-go
          ];

          shellHook = ''
            echo "🚀 Welcome to RobustMQ Development Environment"
            echo "📦 Version: ${version}"
            echo ""
            echo "Available commands:"
            echo "  cargo build                    - Build server components"
            echo "  cargo test                     - Run tests"
            echo "  cargo clippy                   - Run linter"
            echo "  cargo fmt                      - Format code"
            echo "  cd operator && go build        - Build operator"
            echo "  npm run docs:dev               - Start docs dev server"
            echo "  npm run docs:build             - Build documentation"
            echo ""
            echo "Environment:"
            echo "  RUST_VERSION: $(rustc --version)"
            echo "  GO_VERSION: $(go version)"
            echo "  NODE_VERSION: $(node --version)"
            echo ""

            # Set up environment variables
            ${pkgs.lib.concatStringsSep "\n" 
              (pkgs.lib.mapAttrsToList (name: value: "export ${name}=${value}") buildEnv)}
          '';
        };

        # Cross-compilation support
        mkRobustmqServer = pkgs: pkgs.rustPlatform.buildRustPackage {
          pname = "robustmq-server";
          inherit version;
          src = ./.;
          cargoLock = {
            lockFile = ./Cargo.lock;
            allowBuiltinFetchGit = true;
          };
          nativeBuildInputs = with pkgs; [
            rustToolchain
            pkg-config
            protobuf
            cmake
          ];
          buildInputs = with pkgs; [
            openssl
            zlib
            sqlite
          ] ++ lib.optionals pkgs.stdenv.isDarwin [
            pkgs.darwin.apple_sdk.frameworks.Security
          ];
          env = buildEnv // {
            OPENSSL_DIR = "${pkgs.openssl.dev}";
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
          };
          cargoBuildFlags = [
            "--package" "cmd"
            "--bin" "broker-server"
          ];
          doCheck = false;
        };

      in
      {
        packages = {
          default = robustmq-server;
          server = robustmq-server;
          operator = robustmq-operator;
          all = robustmq-all;
          docs = robustmq-docs;
          
          # Cross-compilation packages
          server-x86_64-linux = mkRobustmqServer pkgs.pkgsCross.gnu64;
          server-aarch64-linux = mkRobustmqServer pkgs.pkgsCross.aarch64-multiplatform;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
          server-x86_64-windows = mkRobustmqServer pkgs.pkgsCross.mingwW64;
        } // pkgs.lib.optionalAttrs pkgs.stdenv.isDarwin {
          server-x86_64-darwin = mkRobustmqServer pkgs;
          server-aarch64-darwin = mkRobustmqServer pkgs;
        };

        devShells.default = devShell;

        # Apps for running the binaries
        apps = {
          server = flake-utils.lib.mkApp {
            drv = robustmq-server;
            exePath = "/libs/broker-server";
          };
          
          operator = flake-utils.lib.mkApp {
            drv = robustmq-operator;
            exePath = "/bin/robustmq-operator";
          };
        };

        # Checks for CI/CD
        checks = {
          server-build = robustmq-server;
          operator-build = robustmq-operator;
        };
      }
    );
}
