{
    inputs = {
        nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
        flake-utils.url = "github:numtide/flake-utils";
    }; 
    outputs = { nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
        let
            pkgs = import nixpkgs {
                inherit system;
            };
        in rec {
            devShell = pkgs.mkShell {
                buildInputs = with pkgs; [
                    beam.packages.erlang_27.elixir_1_17
                    lexical
                    nodejs_23
                    nodePackages."@tailwindcss/language-server"
                ];
            };
        }
    );
}
