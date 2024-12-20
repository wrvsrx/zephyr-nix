{
  description = "Build Zephyr projects on Nix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pyproject-nix.url = "github:wrvsrx/pyproject.nix/fix-is-path";
    pyproject-nix.inputs.nixpkgs.follows = "nixpkgs";

    nix-github-actions.url = "github:nix-community/nix-github-actions";
    nix-github-actions.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      pyproject-nix,
      nix-github-actions,
    }:
    (
      let
        inherit (nixpkgs) lib;
        forAllSystems = lib.genAttrs lib.systems.flakeExposed;

        # Flakes output schema shenanigans
        clean = lib.flip removeAttrs [
          "override"
          "overrideDerivation"
          "callPackage"
          "overrideScope"
          "overrideScope'"
          "newScope"
          "packages"
          "sdks"
        ];
      in
      {
        checks = self.packages;

        githubActions = nix-github-actions.lib.mkGithubMatrix {
          # Filter out unversioned (latest SDK) attributes for less CI jobs.
          # These are also tested as explicitly versioned attributes.
          checks = lib.mapAttrs (
            _:
            lib.filterAttrs (
              attr: _:
              !lib.elem attr [
                "hosttools"
                "sdk"
                "sdkFull"
              ]
            )
          ) (nixpkgs.lib.getAttrs [ "x86_64-linux" ] self.checks);
        };

        packages = forAllSystems (
          system:
          let
            pkgs = nixpkgs.legacyPackages.${system};

            packages' = pkgs.callPackage ./. {
              inherit pyproject-nix;
            };

            sdks' = removeAttrs packages'.sdks [ "latest" ];

            inherit (lib) nameValuePair;

          in
          # Again, Flakes output schema is stupid and only allows for a flat attrset, no nested sets.
          # While incredibly unfriendly, fold the nested SDK sets into the packages set to make flakes less pissy.
          clean packages'
          // (lib.listToAttrs (
            lib.concatLists (
              lib.mapAttrsToList (version: v: [
                (nameValuePair "sdk-${version}" v.sdk)
                (nameValuePair "sdkFull-${version}" v.sdkFull)
                (nameValuePair "hosttools-${version}" v.hosttools)
              ]) sdks'
            )
          ))
        );
      }
    );
}
