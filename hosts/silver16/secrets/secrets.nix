let
  # Host key — the machine that decrypts at activation.
  silver16 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA7/v1drJEFf3X22NwB9ygO5V5NaobiQfXYb4LIuFoMP root@silver";

  # Admin keys — able to rotate. Not consumers.
  admins = [
    "age1yubikey1q2hzhr0yekk766v76s5gpsv45t2hl4p644e7w6v77fl30n6qy9keuctu0z6" # pete primary
    "age1yubikey1qdxcmeztxrax00vx5gnyteacgqn7jmdc3qnuvts82rkg2zwwmuccc85afcz" # pete backup
  ];

  hostSecret = {
    publicKeys = [ silver16 ] ++ admins;
  };
in
{
  "p22-build-key.age" = hostSecret;
}
