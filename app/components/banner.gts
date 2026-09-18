// DELIBERATE: a template referencing a `let` binding, which trips
// `ember/template-no-let-reference`. That is an eslint-plugin-ember rule, bridged as
// a JS plugin, running on the AST `ember-eslint-parser` produced. Nothing type-aware
// about it.
let message = 'Reticulating splines';

<template>
  <p class="banner">{{message}}</p>
</template>
