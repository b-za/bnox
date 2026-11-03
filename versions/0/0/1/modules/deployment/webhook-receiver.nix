{ lib, config, pkgs, ... }:
let
  receiverUser = "bnox-webhook-receiver";
  receiverGroup = "bnox-webhook-receiver";
  receiverPort = 8842;
  receiverVhost = "http://bnox-webhook.local";

  handlerSource = ''
    import hashlib
    import hmac
    import json
    import os
    import re
    import subprocess
    from http.server import BaseHTTPRequestHandler, HTTPServer

    SECRETS_ROOT = "/var/lib/bnox/deploy"
    WEBHOOK_PREFIX = "/bnox/webhook/"
    THING_RE = re.compile(r"^[a-zA-Z0-9_-]+$")

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _send(self, status, payload):
            body = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            if not self.path.startswith(WEBHOOK_PREFIX):
                self._send(404, {"error": "not found"})
                return
            thing = self.path[len(WEBHOOK_PREFIX):].split("?", 1)[0].strip("/")
            if not THING_RE.match(thing):
                self._send(404, {"error": "not found"})
                return
            length = int(self.headers.get("content-length", "0"))
            body = self.rfile.read(length) if length > 0 else b""
            signature = self.headers.get("x-hub-signature-256") or self.headers.get("x-forgejo-signature")
            if not signature:
                self._send(401, {"error": "missing signature"})
                return
            try:
                with open(os.path.join(SECRETS_ROOT, thing, "webhook_secret"), "rb") as handle:
                    secret = handle.read().strip()
            except OSError:
                self._send(401, {"error": "no secret configured"})
                return
            expected = signature.split("=", 1)[-1].strip()
            computed = hmac.new(secret, body, hashlib.sha256).hexdigest()
            if not hmac.compare_digest(expected.lower(), computed.lower()):
                self._send(401, {"error": "bad signature"})
                return
            event = {}
            try:
                event = json.loads(body.decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                pass
            envelope = {
                "thing": thing,
                "ref": event.get("ref"),
                "before": event.get("before"),
                "after": event.get("after"),
                "repo": (event.get("repository") or {}).get("full_name"),
                "head_commit": (event.get("head_commit") or {}).get("id"),
            }
            try:
                subprocess.run(
                    ["nats", "pub", "host.deploy." + thing + ".changed", json.dumps(envelope)],
                    check=True,
                    timeout=15,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except (subprocess.SubprocessError, OSError):
                self._send(502, {"error": "nats publish failed"})
                return
            self._send(200, {"ok": True, "thing": thing})

        def log_message(self, *_args):
            pass

    def main():
        host = os.environ.get("BNOX_WEBHOOK_HOST", "127.0.0.1")
        port = int(os.environ.get("BNOX_WEBHOOK_PORT", "8842"))
        server = HTTPServer((host, port), Handler)
        server.serve_forever()

    if __name__ == "__main__":
        main()
  '';

  handlerScript = pkgs.writeText "bnox-webhook-receiver.py" handlerSource;

  natsCli = pkgs.natscli;

  streamConfig = pkgs.writeText "host-deploy-logs.json" (
    builtins.toJSON {
      name = "host-deploy-logs";
      subjects = [ "host.deploy.>" ];
      retention = "limits";
      storage = "file";
    }
  );

  enabledThingsList = lib.mapAttrsToList (
    thingName: thing: thing // { name = thingName; }
  ) (lib.filterAttrs (_: thing: thing.enable) config.bnox.things);

  natsReady = config.services.nats.enable && config.services.nats.jetstream;
in
{
  config = lib.mkMerge [
    {
      users.users.${receiverUser} = {
        isSystemUser = true;
        group = receiverGroup;
        home = "/var/lib/${receiverUser}";
        createHome = true;
      };
      users.groups.${receiverGroup} = { };

      systemd.tmpfiles.rules =
        lib.optional (enabledThingsList != [ ]) "d /var/lib/bnox/deploy 0755 root root -"
        ++ map (thing: "d /var/lib/bnox/deploy/${thing.name} 0750 ${receiverUser} ${receiverGroup} -") enabledThingsList;

      systemd.services.bnox-webhook-receiver = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          BNOX_WEBHOOK_HOST = "127.0.0.1";
          BNOX_WEBHOOK_PORT = toString receiverPort;
        };
        path = [ natsCli ];
        serviceConfig = {
          Type = "simple";
          User = receiverUser;
          Group = receiverGroup;
          ExecStart = "${pkgs.python3}/bin/python3 ${handlerScript}";
          Restart = "on-failure";
          RestartSec = 5;
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = "/var/lib/${receiverUser}";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
          ];
        };
      };

      services.caddy.virtualHosts.${receiverVhost}.extraConfig = ''
        reverse_proxy 127.0.0.1:${toString receiverPort}
      '';
    }

    (lib.mkIf natsReady {
      systemd.services.bnox-nats-stream-init = {
        wantedBy = [ "multi-user.target" ];
        after = [ "nats.service" ];
        requires = [ "nats.service" ];
        path = [ natsCli ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ready=0
          for i in $(seq 1 15); do
            if ${natsCli}/bin/nats stream info host-deploy-logs >/dev/null 2>&1; then
              ${natsCli}/bin/nats stream update host-deploy-logs --config ${streamConfig}
              ready=1
              break
            fi
            if ${natsCli}/bin/nats stream add host-deploy-logs --config ${streamConfig} --defaults >/dev/null 2>&1; then
              ready=1
              break
            fi
            sleep 1
          done
          test "$ready" = "1"
        '';
      };
    })
  ];
}
