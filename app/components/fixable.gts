import type { TOC } from '@ember/component/template-only';

// DELIBERATE: `label` is already a string, so the assertion does nothing --
// `no-unnecessary-type-assertion`, which is auto-fixable. It sits in the script
// half on purpose: fixes only survive where the mapping back to source is
// verbatim, so `--fix` rewrites here and never inside `<template>`.
function shout(label: string): string {
  return (label as string).toUpperCase();
}

export const Fixable: TOC<{ Args: { label: string } }> = <template>
  <p>{{shout @label}}</p>
</template>;

export default Fixable;
