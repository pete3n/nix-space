<div style="display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap;">
  <h1 style="margin: 0;">nix-space - <br> </h1>
    <h3> or <i>How my dotfiles escalated into a multi-platform configuration system for declaratively-configured world domination</i> (working title).</h3>
</div>

# nix-space 
Is a successor to the make-nix project, and is an attempt to implement a modular,
declarative, and reproducible system for deploying infrastructure as code for 
both my home and work networks.

## About
In 2023 I started experimenting with Nix. I thought I could keep it contained to just some 
of my side-projects, but I soon lost control. I had heard about Nix before, but no one ever warned me;
A little Nix on the side quickly became NixOS on my personal computer. In no time, I found myself up
late at nights re-writing my dotfiles, trying to make them more declarative, refactoring my system configuration
in a language I can still barely comprehend. But it wasn't enough. I needed more.

At work the hours dragged on while I suffered on Nixless machines. Just the thought of going eight hours without
re-writing a configuration file into a declarative module with type-checking made me break into a cold sweat.
I needed to find a way to feed my addiction. But there were so many systems out there without Nix, how could
I get my fix? How could I continue to experience the un-paralleled high that only comes from gloriously reproducible software?
