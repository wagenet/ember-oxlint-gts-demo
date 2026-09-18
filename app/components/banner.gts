// DELIBERATE: a template referencing a `let` binding that gets reassigned, which trips
// `ember/template-no-let-reference`: the template never sees the new value. That is an
// eslint-plugin-ember rule, bridged as a JS plugin, running on the AST
// `ember-eslint-parser` produced. Nothing type-aware about it.
let message = 'Reticulating splines';

export function setMessage(next: string): void {
  message = next;
}

<template>
  <p class="banner">{{message}}</p>
</template>
