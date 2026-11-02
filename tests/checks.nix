{
  pkgs,
  nixpkgs,
  bootstrap,
}:
{
  # Exercise all matching tmpfiles z rules: they accumulate, rather than
  # selecting only the first file's rule for a path.
  tun-permissions =
    pkgs.runCommand "container-tun-permissions" { nativeBuildInputs = [ pkgs.systemd ]; }
      ''
        mkdir -p root/etc/tmpfiles.d root/dev/net
        printf 'root:x:%s:%s::/:/bin/sh\n' "$(id -u)" "$(id -g)" > root/etc/passwd
        printf 'root:x:%s:\n' "$(id -g)" > root/etc/group
        cp ${bootstrap.config.environment.etc."tmpfiles.d/static-nodes-permissions.conf".source} \
          root/etc/tmpfiles.d/static-nodes-permissions.conf
        cat > root/etc/tmpfiles.d/00-nixos.conf <<'RULES'
        ${nixpkgs.lib.concatStringsSep "\n" bootstrap.config.systemd.tmpfiles.rules}
        RULES
        touch root/dev/net/tun
        chmod 0666 root/dev/net/tun
        systemd-tmpfiles --root="$PWD/root" --create --prefix=/dev/net/tun
        test "$(stat -c '%a' root/dev/net/tun)" = 600
        touch "$out"
      '';
  shared-modules = bootstrap.config.system.build.toplevel;
}
