{ pkgs, lib, inputs, ... }:
let
  odin = inputs.odin.packages.${pkgs.stdenv.hostPlatform.system}.odin;
in
{
  packages = [ pkgs.gcc pkgs.gf ];

  languages.odin = {
    enable = true;
    # Master build from odin-nightly-flake (not the nixpkgs version)
    package = odin;
    lsp.enable = false;
    debugger = pkgs.gdb;
  };

  env.ODIN_ROOT = "${odin}/share";

  enterShell = ''
    echo ""
    echo "Gauge Devenv"
    echo "  odin:  $(odin version | head -n1)"
    echo ""
  '';
}
