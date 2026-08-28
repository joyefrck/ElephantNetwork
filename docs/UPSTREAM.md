# Upstream maintenance

Elephant Network is a public GPLv3 fork of
[FlClash](https://github.com/chen08209/FlClash). The initial product baseline is
FlClash v0.8.96. Git history is retained rather than copied into a disconnected
repository.

The canonical remotes are:

- `origin`: `https://github.com/joyefrck/ElephantNetwork.git`
- `upstream`: `https://github.com/chen08209/FlClash.git`

Before integrating upstream changes, fetch `upstream/main`, review the complete
diff and release notes, then merge or rebase in a dedicated integration change.
Never overwrite Elephant Network account, managed-profile, distribution, or
in-place-upgrade behavior during an upstream sync.

Every binary release must publish the matching source tag, GPLv3 license,
modification notice, build instructions, and checksums together with the
installers.
