# Type-aware oxlint for Ember `.gts` / `.gjs`

A modern Ember app (Vite, `.gts` components, TypeScript) set up so oxlint's type-aware
rules report inside `<template>`, anchored at the right offsets in the original file.

```
app/components/counter.gts:30:13: error typescript(no-unnecessary-condition): Unnecessary conditional, value is always truthy.
```

Line 30 column 13 is `this.isEnabled`, inside `{{#if}}`, inside `<template>`. Nothing in
the diagnostic refers to generated code.

## Why this needs unreleased builds

Two changes, each on a branch:

|          | change                                                                                                      | PR                                                                 |
| -------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------ |
| oxlint   | route files it only knows through a `languageOptions.parser` override to tsgolint, instead of skipping them | [oxc#26236](https://github.com/oxc-project/oxc/pull/26236)         |
| tsgolint | honor the tsconfig's `contentMappers`, which is how TypeScript 7 hands `.gts` to Glint                      | [tsgolint#1166](https://github.com/oxc-project/tsgolint/pull/1166) |

oxc#26236 builds on [oxc#24262](https://github.com/oxc-project/oxc/pull/24262), which added
custom JS parser support. The oxc#26236 branch already carries those commits, so checking it
out is enough.

There is nothing to `npm install`. Build both from checkouts. Each needs its own setup first:

```sh
# oxc: the branch from oxc#26236, with its JS dependencies installed
git clone -b wagenet/oxlint-gts-typeaware https://github.com/wagenet/oxc.git
(cd oxc && pnpm install)

# tsgolint: the branch from tsgolint#1166, initialized. This is `just init` without the
# e2e setup, and with --depth 1: the submodule is microsoft/TypeScript, and a full clone
# takes a long time.
git clone -b wagenet/tsgolint-content-mappers https://github.com/wagenet/tsgolint.git
(cd tsgolint && git submodule update --init --depth 1 \
  && (cd typescript && git am --3way --no-gpg-sign ../patches/*.patch) \
  && mkdir -p internal/collections \
  && find typescript/tsc/internal/collections -type f ! -name '*_test.go' -exec cp {} internal/collections/ \;)

# then, in this repo
OXC_DIR=$PWD/oxc TSGOLINT_DIR=$PWD/tsgolint scripts/build-oxlint.sh
pnpm install
pnpm lint:oxlint
```

Both this repo and oxc pin pnpm 12 through `packageManager`. An older global pnpm cannot read
their lockfiles, and pnpm older than 9.7 does not switch versions on its own.

`scripts/build-oxlint.sh` stages the pair into `.oxlint-internal/` (gitignored, ~36MB) and
writes a `BUILD-INFO` recording which commits went in. `bin/oxlint` sets `OXLINT_TSGOLINT_PATH` and
runs the staged CLI, and does nothing else. Everything after it is ordinary oxlint. Set `OXLINT_INTERNAL_DIR` to reuse a build staged somewhere else.

Requirements: Node matching `^22.21.1 || >=24.10.0`, which is `ember-content-mapper`'s own
range and applies because it spawns a bare `node` (23.x does not qualify). Plus Go 1.26 or
later and Rust toolchains for the two builds. Verified on darwin-arm64.

## How a `.gts` file gets linted

One config override drives three passes:

```ts
// oxlint.config.mts
overrides: [
  {
    files: ['**/*.{gjs,gts}'],
    languageOptions: { parser: 'ember-eslint-parser' },
  },
],
```

1. JS-plugin pass. `ember-eslint-parser` parses the file, and bridged ESLint-plugin rules
   run on that AST. `ember/template-no-let-reference` below is one.
2. Native pass. oxlint's own Rust rules run against a _shadow source_ derived from that
   parse, which is why template usage counts. See `greeting.gts`.
3. Type-aware pass. The override's _presence_ is what makes an extension oxlint does not
   recognize eligible for tsgolint. The parsed AST is never handed over: tsgolint receives
   the original path and re-derives the content itself through `contentMappers`, which runs
   `ember-content-mapper` (wrapping Glint) to produce TypeScript for typescript-go to check.

So a `.gts` is parsed twice by two different things: `ember-eslint-parser` for the rules
that run in-process, `ember-content-mapper` for the type-aware ones.

Eligibility and permission are separate. Content mappers are project code that tsgolint
executes, so TypeScript keeps the underlying option command-line-only and off by default,
because a checked-in config must not be able to grant a repo the right to run its own code.
Hence `--run-external-code`, which a `languageOptions.parser` override deliberately does
not imply. It is the one thing the lint scripts pass on the command line; everything else,
`typeAware` included, lives in `oxlint.config.mts` where an editor can read it too.

## What it reports

`pnpm lint:oxlint` is expected to fail: the findings are the demo. The first four are marked
`DELIBERATE` in the source. The last is ESLint's own finding on the same code, reported
because the config ports ESLint's rules (see [the comparison](#setup-relative-to-a-stock-blueprint)).

| file                                | finding                                                                         | which pass |
| ----------------------------------- | ------------------------------------------------------------------------------- | ---------- |
| `app/components/counter.gts:30`     | `typescript(no-unnecessary-condition)` on `this.isEnabled`, inside `<template>` | type-aware |
| `app/components/save-button.gts:15` | `typescript(no-floating-promises)` in the script half                           | type-aware |
| `app/components/fixable.gts:8`      | `typescript(no-unnecessary-type-assertion)`, auto-fixable                       | type-aware |
| `app/components/banner.gts:12`      | `ember(template-no-let-reference)` on `{{message}}`                             | JS plugin  |
| `app/components/save-button.gts:15` | `warp-drive(no-legacy-request-patterns)` on `this.args.save()`                  | JS plugin  |

The negative case:

| file                          | what must not happen                                                                                                                                                                      |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `app/components/greeting.gts` | `formatName` is imported and used only inside `<template>`. `eslint/no-unused-vars` is on and correctly stays quiet. Add an import that really is unused and it reports that one instead. |

### Fixes stop at the template boundary

Fixes only survive where the mapping back to source is verbatim, so `--fix` rewrites script
sections and leaves `<template>` alone:

```
pnpm lint:oxlint:fix
  fixable.gts   (label as string).toUpperCase()  ->  (label).toUpperCase()   # fixed
  counter.gts   {{#if this.isEnabled}}                                       # unchanged
```

A `.gts` diagnostic can arrive with no fix attached. That is expected. (`--fix` leaves the
now-redundant parens; `pnpm format` cleans them up.)

## Telling a mapper problem from a rule problem

Drop the `languageOptions.parser` override and the file stops being eligible at all, so you
get silence instead of a misleading diagnostic:

```
$ bin/oxlint -c without-the-override.mts --run-external-code app/components/counter.gts
No files found to lint. Please check your paths and ignore patterns.
```

Misspell the mapper package and both halves say so:

```
tsconfig.json:20:18: error typescript(tsconfig-error): Invalid tsconfig
  help: The content mapper package 'ember-content-mapper-typo' could not be resolved.
app/components/counter.gts:1:1: error typescript(unsupported-file-extension): Unsupported file extension
  help: tsgolint cannot type-check .gts files on their own. Register a TypeScript content
        mapper for the extension in the "contentMappers" of the tsconfig that includes this file.
```

You only get the `tsconfig-error` that explains it when the lint set includes at least one
natively parseable file from that tsconfig. Programs are built per requested file, so
linting a single `.gts`, which is every editor request, gets the bare
`unsupported-file-extension` and no reason for it.

## Setup, relative to a stock blueprint

Generated with `pnpm dlx ember-cli@latest new ember-oxlint-gts-demo --typescript --pnpm`
(ember-cli 7.2, Vite 8, Embroider, `.gts` by default), then:

`tsconfig.json` gains the entry that makes `.gts` type-checkable at all:

```jsonc
"contentMappers": [
  { "package": "ember-content-mapper", "extensions": [".gts", ".gjs"] }
]
```

`package.json` gains `ember-content-mapper`, `ember-eslint-parser` (oxlint resolves
`languageOptions.parser` as a bare specifier from the package being linted, so it is
declared directly rather than leaned on transitively), `@glint/ember-tsc` pinned to the
`~1.11` line the mapper wants, and TypeScript twice:

```jsonc
"typescript": "^6.0.3",                                  // typescript-eslint, @glint/ember-tsc
"typescript-7": "npm:typescript@7.1.0-dev.20260901.1"    // reads contentMappers
```

`lint:types` runs the TypeScript 7 copy as `tsc --noEmit --runExternalCode`. Both copies are
load-bearing. tsgolint has typescript-go compiled in and does the checking, but the mapper
runs Glint in Node, and `@glint/ember-tsc` peer-depends on `typescript >=5.6.0`, so the
type-aware pass needs the TypeScript 6 copy installed as well.

`.gts` and `.gjs` imports need an explicit extension, or you get `TS2307 Cannot find
module`. The extension is the part that matters, not the style of specifier:
`ember-oxlint-gts-demo/components/counter.gts` resolves through the `paths` alias just as
`./counter.gts` does, while `./counter` fails.

The blueprint's ESLint, Prettier, stylelint and template-lint are all left in place, which
makes the gap measurable. `@typescript-eslint/no-unnecessary-condition` is not in the
blueprint's `recommendedTypeChecked` set; enable it on the ESLint side and put the same
always-truthy check in three places:

| site                        | ESLint + typescript-eslint | oxlint  |
| --------------------------- | -------------------------- | ------- |
| a `.ts` file                | reports                    | reports |
| the script half of a `.gts` | reports                    | reports |
| inside `<template>`         | silent                     | reports |

Same rule, both sides. Everything else ESLint reports here, oxlint reports too, because
`oxlint.config.mts` builds its rules from the presets `eslint.config.mjs` uses, block for
block. Plugins oxlint does not implement natively (ember, warp-drive, qunit, n) run bridged
through `jsPlugins`. Per file type, every rule ESLint enables is enabled in oxlint except
three: `no-dupe-args` and `no-octal`, which strict mode turns into syntax errors the parser
reports, and `ember/require-return-from-computed` in `.gjs`/`.gts` (see below). On top of
that, oxlint adds its `correctness` category and `no-unnecessary-condition`, and the
template finding is the one ESLint cannot reach.

The config is `.mts` rather than `.ts` because `package.json` has no `"type": "module"`,
and without it Node warns on every run.

There is no CI here: `pnpm lint` cannot run anywhere the two binaries have not been built by
hand.

## Editor

Not reachable yet. `--run-external-code` has no config equivalent by design, and the
language server takes the permission from the client rather than from a file in the
repository, so an editor needs a client that can send it.
[oxc-vscode#374](https://github.com/oxc-project/oxc-vscode/pull/374) adds that as an
`oxc.runExternalCode` setting, gated on VS Code workspace trust: the value is ignored when
it comes from a checked-in `.vscode/settings.json` in a workspace you have not trusted. That
PR is draft and waits on the oxlint server side, so for now a `.gts` opened in an editor
reports `unsupported-file-extension`.

When it lands, these are the paths to point at a local build:

```jsonc
{
  "oxc.path.oxlint": "${workspaceFolder}/.oxlint-internal/oxlint/bin/oxlint",
  "oxc.path.tsgolint": "${workspaceFolder}/.oxlint-internal/bin/tsgolint",
  "oxc.typeAware": true,
  "oxc.runExternalCode": true,
}
```

## What is not covered

- Template-shaped rules. oxlint has no native `ember` plugin and no template linting.
  `eslint-plugin-ember` rules run bridged, and rules needing `getScope()`-style resolution
  on the Glimmer AST remain blocked. See
  [oxlint-gjs-experiments](https://github.com/NullVoxPopuli-ai-agent/oxlint-gjs-experiments)
  for how far that goes.
- Bridged rules using code-path analysis. oxlint's JS-plugin bridge rejects
  `onCodePathStart` under a custom parser. `ember/require-return-from-computed` is enabled
  here and turned back off in the `.gts` override to show the shape of the workaround.
  Leave it on and every `.gts` gets this instead of a report:

  ```
  app/components/counter.gts: error: Error running JS plugin.
    Error: Rules using code path analysis ('onCodePathStart') are not supported
           for files parsed by a custom parser
  ```

  It takes down the whole JS-plugin pass for that file. The type-aware pass runs separately
  and is unaffected, so `no-unnecessary-condition` still reports while the ember rules go
  missing. That combination reads like a rule that found nothing.

- Bridged rules needing type information. The bridge supplies no parser services, and
  tsgolint does not run bridged rules, so there is nowhere for a type-checked ESLint rule to
  work. Not tested in this repo.
- Diagnostics whose fix cannot be expressed in the template. `typescript/dot-notation` is
  the clearest case. Blocks are property accesses in the mapped TypeScript, so enabling the
  rule reports against the component's caller:

  ```
  app/templates/application.gts:14:9: error typescript(dot-notation): ["default"] is better written in dot notation.
  app/templates/application.gts:17:9: error typescript(dot-notation): ["actions"] is better written in dot notation.
  ```

  Neither `.default` nor `.actions` is something you can write in a template, so the fix has
  nowhere to go. Not enabled here.

- Linux and CI. Only built and run on darwin-arm64.

## Prior art

- [`NullVoxPopuli/ember-content-mapper`](https://github.com/NullVoxPopuli/ember-content-mapper):
  the mapper, and `examples/cli-app`, the same blueprint wired for TypeScript 7
  type-checking with linting deliberately stripped. This repo is that setup plus the
  linting.
- `apps/oxlint/fixtures/cli/tsgolint_external_parser` in the oxc branch: the four-file
  fixture this demo expands on.
