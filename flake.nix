{
  description = "worker - More comfort for https://android.googlesource.com/tools/repo";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAll = f: nixpkgs.lib.genAttrs systems (s: f nixpkgs.legacyPackages.${s});
    in {
      packages = forAll (pkgs: {
        default = pkgs.buildDubPackage {
          pname = "worker";
          version = self.shortRev or "dirty";
          src = ./.;
          dubLock = ./dub-lock.json;
          dubBuildFlags = [ "--config=application" ];
          installPhase = ''
            runHook preInstall
            install -Dm755 out/main/worker -t $out/bin
            runHook postInstall
          '';
        };
      });
    };
}
