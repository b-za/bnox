{ lib }:

{
  mkEnvFile = lines: lib.concatStringsSep "\n" lines + "\n";
}
