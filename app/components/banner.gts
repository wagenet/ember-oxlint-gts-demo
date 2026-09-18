// DELIBERATE: a template referencing a `let` binding -- `ember/template-no-let-reference`.
// An eslint-plugin-ember rule, bridged as a JS plugin, running on the AST that
// `ember-eslint-parser` produced. Nothing type-aware about it.
let message = 'Reticulating splines';

<template>
  <p class="banner">{{message}}</p>
</template>
