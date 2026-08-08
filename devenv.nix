{ pkgs, lib, inputs, ... }:
let
  odin = inputs.odin.packages.${pkgs.stdenv.hostPlatform.system}.odin;
in
{
  # Graphical debugger frontend for gdb (opens in the browser).
  packages = [ pkgs.gdbgui ];

  languages.odin = {
    enable = true;
    # Master build from odin-nightly-flake (not the nixpkgs version)
    package = odin;
    # No Odin language server
    lsp.enable = false;
    # GDB for real debugging (build with `odin build . -debug`)
    debugger = pkgs.gdb;
  };

  env.ODIN_ROOT = "${odin}/share";

  enterShell = ''
    echo ""
    echo "LondoLang Devenv"
    echo "  odin:  $(odin version | head -n1)"
    echo ""
  '';
}
