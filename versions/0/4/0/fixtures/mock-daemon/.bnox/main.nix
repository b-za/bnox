{
  shape = "daemon";
  runtime = "host-install";
  execStart = "/var/lib/mock-daemon/run";
  ingressPort = null;
  natsSubject = null;
  secrets = [ "token" ];
}
