let
  # idm1's host key, so the running Identity Node can decrypt its own CA
  # material at activation. Fill this in from the deployed host during the
  # bootstrap:
  #   ssh pete@idm1.p22.lan 'cat /etc/ssh/ssh_host_ed25519_key.pub'
  idm1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDtsO+uA6qZVCGApQHGQ4P0NkOXozp+Kwt0XBZXRQa/W root@idm1";

  # YubiKeys, so the admin can (re)encrypt these secrets off-host.
  pete_yk_pri = "age1yubikey1q2hzhr0yekk766v76s5gpsv45t2hl4p644e7w6v77fl30n6qy9keuctu0z6";
  pete_yk_bak = "age1yubikey1qdxcmeztxrax00vx5gnyteacgqn7jmdc3qnuvts82rkg2zwwmuccc85afcz";

  caRecipients = [
    idm1
    pete_yk_pri
    pete_yk_bak
  ];
in
{
  # step-ca's intermediate private key and the password protecting it.
  "step-ca/intermediate.key.age".publicKeys = caRecipients;
  "step-ca/intermediate.password.age".publicKeys = caRecipients;

  # SSH certificate authority signing keys - host CA and user CA
  "step-ca/ssh_host_ca.age".publicKeys = caRecipients;
  "step-ca/ssh_user_ca.age".publicKeys = caRecipients;
}
