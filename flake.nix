{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
        nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
    }; 
    outputs = { nixpkgs, flake-utils, nix-vscode-extensions, ... }: flake-utils.lib.eachDefaultSystem (system:
        let
            pkgs = import nixpkgs {
                inherit system;
            };
            extensions = nix-vscode-extensions.extensions.${system};
            inherit (pkgs) vscode-with-extensions vscode;
            packages.default = vscode-with-extensions.override {
              vscode = vscode;
              vscodeExtensions = [
                extensions.vscode-marketplace.ms-vsliveshare.vsliveshare
              ];
            };
        in rec {
            devShell = pkgs.mkShell {
                buildInputs = with pkgs; [
                    beam.packages.erlang_27.elixir_1_18
                    lexical
                    nodejs_23
                    nodePackages."@tailwindcss/language-server"
                    packages.default
                ];
            };
        }
    );
}
