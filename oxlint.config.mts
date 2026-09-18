/**
 * Rules come from the presets eslint.config.mjs uses, block for block, so oxlint runs
 * everything ESLint does here. Plugins oxlint does not implement natively (ember,
 * warp-drive, qunit, n) run bridged through jsPlugins. The additions are the `correctness`
 * category and the type-aware `typescript/no-unnecessary-condition`.
 */
import js from '@eslint/js';
import ts from 'typescript-eslint';
import ember from 'eslint-plugin-ember/recommended';
import WarpDrive from 'eslint-plugin-warp-drive/recommended';
import eslintConfigPrettier from 'eslint-config-prettier';
import qunit from 'eslint-plugin-qunit';
import n from 'eslint-plugin-n';

type Rules = Record<string, unknown>;

// ESLint rules oxlint does not have. An unknown rule name fails the whole config, even
// one being turned off. Strict mode makes the first two syntax errors, which the parser
// reports; `no-new-symbol` is deprecated for `no-new-native-nonconstructor`, which is on.
const NOT_IN_OXLINT = ['no-dupe-args', 'no-octal', 'no-new-symbol'];

// typescript-eslint extension rules whose oxlint equivalent is the core rule, which
// already understands TypeScript.
const CORE_IN_OXLINT = [
  'no-array-constructor',
  'no-unused-expressions',
  'no-unused-vars',
];

// typescript-eslint's rules are `typescript/*` in oxlint. Its presets turn a core rule off
// and its extension on; both land on one name here, so the extension is applied last.
function port(...ruleSets: (Rules | undefined)[]): Rules {
  const entries = ruleSets.flatMap((set) => Object.entries(set ?? {}));
  const isTs = ([name]: [string, unknown]) =>
    name.startsWith('@typescript-eslint/');
  const rules: Rules = {};
  for (const [name, value] of [
    ...entries.filter((e) => !isTs(e)),
    ...entries.filter(isTs),
  ]) {
    const bare = name.replace(/^@typescript-eslint\//, '');
    const ported =
      name === bare || CORE_IN_OXLINT.includes(bare)
        ? bare
        : `typescript/${bare}`;
    rules[ported] = value;
  }
  for (const name of NOT_IN_OXLINT) delete rules[name];
  return rules;
}

// eslint-config-prettier comes after these blocks in eslint.config.mjs, so whatever it
// turns off stays off.
function withoutPrettier(rules: Rules): Rules {
  return Object.fromEntries(
    Object.entries(rules).filter(
      ([name]) => !(name in eslintConfigPrettier.rules),
    ),
  );
}

const typeChecked = ts.configs.recommendedTypeChecked.map(
  (config) => config.rules,
);

export default {
  plugins: ['eslint', 'typescript', 'oxc', 'import', 'promise', 'unicorn'],
  jsPlugins: [
    'eslint-plugin-ember',
    'eslint-plugin-warp-drive',
    'eslint-plugin-qunit',
    // `node` is oxlint's native plugin, which implements few of these rules.
    { name: 'n', specifier: 'eslint-plugin-n' },
  ],
  categories: {
    correctness: 'error',
  },
  options: {
    typeAware: true,
    reportUnusedDisableDirectives: 'error',
  },
  rules: withoutPrettier(
    port(
      js.configs.recommended.rules,
      ...WarpDrive.map((config) => config.rules),
    ),
  ),
  overrides: [
    {
      files: ['**/*.{js,ts}'],
      rules: withoutPrettier(port(ember.configs.base.rules)),
    },
    {
      files: ['**/*.{gjs,gts}'],
      languageOptions: {
        parser: 'ember-eslint-parser',
      },
      rules: {
        ...withoutPrettier(port(ember.configs.gts.rules)),
        // Uses code-path analysis, which oxlint's JS-plugin bridge rejects under a custom
        // parser. Left on, it fails the whole JS-plugin pass for the file. See README.md.
        'ember/require-return-from-computed': 'off',
      },
    },
    {
      files: ['**/*.{js,gjs}'],
      env: { browser: true },
    },
    {
      files: ['**/*.{ts,gts}'],
      env: { browser: true },
      rules: {
        ...port(ts.configs.eslintRecommended.rules, ...typeChecked),
        'typescript/no-unnecessary-condition': 'error',
      },
    },
    {
      files: ['tests/**/*-test.{js,gjs,ts,gts}'],
      rules: port(qunit.configs.recommended.rules),
    },
    {
      files: ['**/*.cjs', 'config/**/*.js'],
      env: { node: true },
      rules: port(n.configs['flat/recommended-script'].rules),
    },
    {
      files: ['**/*.mjs'],
      env: { node: true },
      rules: port(n.configs['flat/recommended-module'].rules),
    },
  ],
  ignorePatterns: ['/dist', '/coverage', '/declarations', '/.oxlint-internal'],
};
