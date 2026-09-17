# Terminal multiplexers module.
#
# Both the tmux and zellij modules define an `ssh` shell function and a prompt
# hook, and both contribute them through nixSpace.programs.shells.initExtra,
# so they clobber each other and need an assertion to protect against.
#
{
  config,
  ...
}:
let
  tmux = config.nixSpace.programs.multiplexers.tmux;
  zellij = config.nixSpace.programs.multiplexers.zellij;

  # Enabling both multiplexers without the shell hooks is fine: they are separate
  # programs with separate config and nothing shared.
  tmuxHooks = tmux.enable && (tmux.sshRename || tmux.windowTitle);
  zellijHooks = zellij.enable && (zellij.sshRename || zellij.tabTitle);
in
{
  imports = [
    ./tmux
    ./zellij
  ];

  config.assertions = [
    {
      assertion = !(tmuxHooks && zellijHooks);
      message = ''
        nixSpace.programs.multiplexers: tmux and zellij both have shell hooks
        enabled, and they define the same shell functions, whichever is
        sourced last wins, and will fail inside the other multiplexer.

        Both programs can be enabled together; it is the hooks that
        collide. Turn off sshRename and windowTitle on one of them:

          nixSpace.programs.multiplexers.tmux.sshRename = false;
          nixSpace.programs.multiplexers.tmux.windowTitle = false;

        or the zellij equivalents, sshRename and tabTitle.
      '';
    }
  ];
}
