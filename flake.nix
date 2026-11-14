# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later
{
  description = "Imladris — Native Linux Scientific Workbench & Polyglot Notebook Studio";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.stdenv.mkDerivation {
            pname = "imladris";
            version = "0.25.0";

            src = self;

            nativeBuildInputs = with pkgs; [
              meson
              ninja
              pkg-config
              vala
              wrapGAppsHook4
              desktop-file-utils
              appstream-glib
            ];

            buildInputs = with pkgs; [
              glib
              gtk4
              libadwaita
              gtksourceview5
              webkitgtk_6_0
              libsoup_3
              json-glib
              libsecret
              libgee
              gsettings-desktop-schemas
            ];

            mesonFlags = [
              "-Dbuildtype=release"
            ];

            meta = with pkgs.lib; {
              description = "Native scientific notebook studio for Quarto, R, Python, and Jupyter";
              homepage = "https://antux912012.github.io/imladris/";
              license = licenses.gpl3Plus;
              mainProgram = "imladris";
              platforms = platforms.linux;
            };
          };
        });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShell {
            inputsFrom = [ self.packages.${system}.default ];
            packages = with pkgs; [
              gdb
              git
            ];
          };
        });
    };
}
