# {{crate}}

Say the one thing this command does, in one sentence.

Then say what problem it solves and why the obvious alternative is worse. Two short
paragraphs are enough. The CLI section below is generated from the crate's `//!`
docs, so this is the only place a reader learns the motivation.

## Installation

```
nix run github:sshine/example
nix profile install github:sshine/example
cargo install example
```

You can download prebuilt [static binaries for x86_64 and aarch64 Linux][releases].

### NixOS

The flake exports an overlay, so a system configuration can take example as an
ordinary attribute of `pkgs`:

```nix
{
  inputs = {
    nixpkgs.url = "https://nixos.org/channels/nixpkgs-unstable/nixexprs.tar.xz";

    example = {
      url = "github:sshine/example";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, example, ... }:
    {
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        modules = [
          (
            { pkgs, ... }:
            {
              nixpkgs.overlays = [ example.overlays.default ];
              environment.systemPackages = [ pkgs.example ];
            }
          )
        ];
      };
    };
}
```

The overlay builds against your nixpkgs rather than this flake's, so `overrideAttrs`
and cross-compilation work as they do for anything else in the set. Where none of
that matters, `example.packages.${system}.default` is the same package without the
overlay.

## CLI

{{readme}}

## License

MIT OR Apache-2.0.

[releases]: https://github.com/sshine/example/releases
