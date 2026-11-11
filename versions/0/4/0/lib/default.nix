{ lib }:

{
  # D-020 §2 — container image for a bnox thing. Bare dockerTools roots lack
  # what ordinary software assumes, and each gap was found the hard way on
  # agenthub: no /etc/passwd → Go's os/user fails, natscli dies (G18); a
  # buildEnv drops everything not in pathsToLink (G19); no CA store → every
  # HTTPS call fails, first noticed live (G30). This always bakes:
  # /etc/passwd + /etc/group (root, nobody), HOME=/root, CA certificates
  # (/etc/ssl/certs/ca-certificates.crt + ca-bundle.crt, SSL_CERT_FILE), /tmp.
  #
  #   images.x86_64-linux.main = bnox.lib.mkImage {
  #     inherit pkgs; name = "myapp-main"; contents = [ myapp ];
  #     entrypoint = [ "/bin/myapp" ];
  #   };
  mkImage =
    {
      pkgs,
      name,
      tag ? "current",
      contents ? [ ],
      entrypoint ? null,
      env ? [ ],
      config ? { },
    }:
    pkgs.dockerTools.buildImage {
      inherit name tag;
      copyToRoot = pkgs.buildEnv {
        name = "${name}-root";
        paths = [
          pkgs.dockerTools.fakeNss
          pkgs.dockerTools.caCertificates
          (pkgs.runCommand "${name}-dirs" { } "mkdir -p $out/tmp $out/root")
        ] ++ contents;
        pathsToLink = [ "/" ];
      };
      extraCommands = "chmod 1777 tmp 2>/dev/null || true";
      config =
        {
          Env = [
            "HOME=/root"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          ] ++ env;
        }
        // lib.optionalAttrs (entrypoint != null) { Entrypoint = entrypoint; }
        // config;
    };
}
