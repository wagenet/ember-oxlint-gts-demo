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

There is nothing to `npm install`. Build both from checkouts:

```sh
OXC_DIR=/path/to/oxc TSGOLINT_DIR=/path/to/tsgolint scripts/build-oxlint.sh
pnpm install
pnpm lint:oxlint
```

`scripts/build-oxlint.sh` stages the pair into `.oxlint-internal/` (gitignored, ~35MB) and
writes a `BUILD-INFO` recording which commits went in. `bin/oxlint` is a three-line wrapper
that sets `OXLINT_TSGOLINT_PATH` and runs the staged CLI. Everything after it is ordinary
oxlint. Set `OXLINT_INTERNAL_DIR` to reuse a build staged somewhere else.

Requirements: Node >= 22.21.1 (`ember-content-mapper` spawns a bare `node`), plus Go and
Rust toolchains for the two builds. Verified on darwin-arm64.

## How a `.gts` file gets linted

One config override drives three passes:

```jsonc
// .oxlintrc.json
"overrides": [
  {
    "files": ["**/*.{gjs,gts}"],
    "languageOptions": { "parser": "ember-eslint-parser" }
  }
]
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
`typeAware` included, lives in `.oxlintrc.json` where an editor can read it too.

## What it reports

`pnpm lint:oxlint` is expected to fail: the findings are the demo. Each one is marked
`DELIBERATE` in the source.

| file                                | finding                                                                         | which pass |
| ----------------------------------- | ------------------------------------------------------------------------------- | ---------- |
| `app/components/counter.gts:30`     | `typescript(no-unnecessary-condition)` on `this.isEnabled`, inside `<template>` | type-aware |
| `app/components/save-button.gts:15` | `typescript(no-floating-promises)` in the script half                           | type-aware |
| `app/components/fixable.gts:8`      | `typescript(no-unnecessary-type-assertion)`, auto-fixable                       | type-aware |
| `app/components/banner.gts:8`       | `ember(template-no-let-reference)` on `{{message}}`                             | JS plugin  |

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

Drop the `.gts` override and the file stops being eligible at all, so you get silence
instead of a misleading diagnostic:

```
$ bin/oxlint -c without-the-override.json app/components/counter.gts
No files found to lint. Please check your paths and ignore patterns.
```

Misspell the mapper package and both halves say so:

```
tsconfig.json:30:18: error typescript(tsconfig-error): Invalid tsconfig
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

`lint:types` runs the TypeScript 7 copy as `tsc --noEmit --runExternalCode`. oxlint needs
neither copy: tsgolint has typescript-go compiled in.

`.gts` and `.gjs` imports need explicit extensions (`./counter.gts`, not
`ember-oxlint-gts-demo/components/counter`). The `paths` alias resolves `.ts` but not
`.gts`, and you get `TS2307 Cannot find module` if you forget.

The blueprint's ESLint, Prettier, stylelint and template-lint are all left in place. ESLint
finds the same two findings oxlint does in `banner.gts` and `save-button.gts`, plus
`prefer-const` and a `warp-drive` rule this oxlint config does not cover: `correctness` is
the only category enabled, and `eslint-plugin-warp-drive` is not in `jsPlugins`.

The generated GitHub Actions workflow was removed, since `pnpm lint` cannot run anywhere
the two binaries have not been built by hand.

## Editor

The stock oxc VS Code extension can do this, with one caveat. `--run-external-code` has no
config equivalent by design, and the language server takes the permission from the client,
so type-aware `.gts` in an editor needs a build that defaults it on. That is a local patch,
absent from the PR branches.

```jsonc
{
  "oxc.path.oxlint": "${workspaceFolder}/.oxlint-internal/oxlint/bin/oxlint",
  "oxc.path.tsgolint": "${workspaceFolder}/.oxlint-internal/bin/tsgolint",
  "oxc.typeAware": true,
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
  work.
- Diagnostics whose fix cannot be expressed in the template. `typescript/dot-notation` is
  the clearest case: a named block `<:actions>` becomes `blocks["actions"]` in the mapped
  TypeScript, and `.actions` is not something you can write in a template. Not enabled here.
- Linux and CI. Only built and run on darwin-arm64.

## Prior art

- [`NullVoxPopuli/ember-content-mapper`](https://github.com/NullVoxPopuli/ember-content-mapper):
  the mapper, and `examples/cli-app`, the same blueprint wired for TypeScript 7
  type-checking with linting deliberately stripped. This repo is that setup plus the
  linting.
- `apps/oxlint/fixtures/cli/tsgolint_external_parser` in the oxc branch: the four-file
  fixture this demo expands on.
