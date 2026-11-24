# Contributing

Thanks for helping. Bug reports, rule corrections (especially regional Belot and Santase variants),
translations and code are all welcome.

## Before you start

- For anything larger than a small fix, open an issue first so we can agree on the approach.
- Security problems (cheating, ledger tampering): report them privately, see [SECURITY.md](SECURITY.md).

## Development

- The addon is plain **Lua 5.1** (WoW client). The tests run outside the game with stubbed WoW APIs:
  ```sh
  bash t.sh                  # all tests (needs LuaJIT or Lua 5.1)
  bash t.sh tests/engines    # one folder
  ```
- Game engines (`engines/`) are pure and deterministic: every client runs the same code on the same
  events, so no randomness, clock or WoW API inside an engine.
- `tools/sim/` has large simulations of every game (`luajit tools/sim/<game>_soak.lua [n] [seed]`);
  run the one for the game you change.
- Every user-facing text goes into both `locale/en.lua` and `locale/bg.lua`.
- `tests/toc_test.lua` keeps files small; split a helper out rather than raising a limit.
- Network messages must stay compatible with the previous release: add optional fields, do not
  change the meaning of existing ones.

## Pull requests

- `master` is protected: every change goes through a pull request, and the `test` check must pass.
- Keep a pull request to one change, with a test that fails without it.
- Describe how you tested it (and in game, if it touches the interface).

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
