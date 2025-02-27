# nnl: nim nix lock

Alternative implementation of `nim_lk` that performs
no version/dependency inference and simply translates a
`nimble.lock` file to the necessary `lock.json` for building with `nix`.

## Usage

```sh
nix run "github:daylinmorgan/nnl" nimble.lock > lock.json
nix run "github:daylinmorgan/nnl" nimble.lock --output lock.json
nix run "github:daylinmorgan/nnl" nimble.lock -o:lock.json
```

