# pin nixpkgs to NixOS 21.05 release
with (import (fetchTarball "https://github.com/NixOS/nixpkgs/archive/f77036342e2b690c61c97202bf48f2ce13acc022.tar.gz") {});
mkShell {
  buildInputs = [
    julia-stable # that's Julia 1.5.4
    parallel
    coreutils    # timeout

    # need these two to download package sources:
    wget
    cacert

    # convinience
    less
  ];
}

