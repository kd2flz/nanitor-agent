{ stdenvNoCC, lib, dpkg, autoPatchelfHook, makeWrapper, openssl, zlib, curl, util-linux, systemd, gcc, src }:

stdenvNoCC.mkDerivation {
  pname = "nanitor-agent";
  version = "latest";
  inherit src;
  dontUnpack = true;

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    openssl      # libcrypto, libssl
    zlib         # libz
    curl         # libcurl
    util-linux   # libuuid, etc.
    systemd      # libsystemd (if the agent links to it)
    gcc.cc.lib   # libstdc++ and libgcc_s
  ];

  installPhase = ''
    mkdir -p $out
    # Extract the Debian package into $out
    dpkg-deb -x "$src" "$out"

    # Many .deb files put stuff under usr/; flatten that into $out.
    if [ -d "$out/usr" ]; then
      # Move everything from $out/usr/* to $out/
      shopt -s dotglob
      mv $out/usr/* $out/
      rmdir $out/usr || true
      shopt -u dotglob
    fi

    # Some agents install binaries under sbin; ensure they are in bin/
    if [ -d "$out/sbin" ]; then
      mkdir -p $out/bin
      shopt -s nullglob
      mv $out/sbin/* $out/bin/ || true
      shopt -u nullglob
      rmdir $out/sbin || true
    fi

    # If the binary is elsewhere, you can locate and symlink it here:
    if [ ! -x "$out/bin/nanitor-agent" ]; then
      # Try to find it and link
      BIN_PATH=$(find "$out" -type f -name nanitor-agent -perm -111 | head -n1 || true)
      if [ -n "$BIN_PATH" ]; then
        mkdir -p $out/bin
        ln -s "$BIN_PATH" $out/bin/nanitor-agent
      fi
    fi

    # We do NOT install Debian service files; NixOS will provide its own unit.
    rm -rf "$out/etc" "$out/var" || true
  '';

  # If you want to quickly verify binary runs, uncomment this:
  # installCheckPhase = ''
  #   if [ -x "$out/bin/nanitor-agent" ]; then
  #     "$out/bin/nanitor-agent" --version || true
  #   fi
  # '';

  meta = with lib; {
    description = "Nanitor agent repackaged from a Debian .deb for Nix/NixOS";
    license = licenses.unfree; 
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    maintainers = [ "David Rhoads" ];
  };
}
