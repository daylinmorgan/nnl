# nnl: nim nix lock

`nnl` is designed to generate a [`nimBuildPackage`][nimBuildPackageUrl] compatible `lock.json`.
It offloads all version resolution to `nimble`.

If your project has an existing `nimble.lock` it will convert this directly,
otherwise it will first generate a `nimble.lock` behind the scenes to be consumed by `nnl`.

## usage

```sh
nix run "github:daylinmorgan/nnl" nimble.lock > lock.json
nix run "github:daylinmorgan/nnl" nimble.lock --output lock.json
nix run "github:daylinmorgan/nnl" nimble.lock -o:lock.json
nix run "github:daylinmorgan/nnl" . -o lock.json --git hwylterm
```

## alternatives

- [nim_lk](https://git.sr.ht/~ehmry/nim_lk)
- [nim2nix](https://github.com/daylinmorgan/nim2nix)

[nimBuildPackageUrl]: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/nim.section.md#buildnimpackage-buildnimpackage
