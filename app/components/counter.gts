import Component from '@glimmer/component';
import { tracked } from '@glimmer/tracking';
import { on } from '@ember/modifier';

export interface CounterSignature {
  Args: {
    start?: number;
    step?: number;
  };
  Blocks: {
    default: [count: number];
    actions: [];
  };
  Element: HTMLDivElement;
}

export default class Counter extends Component<CounterSignature> {
  @tracked count = this.args.start ?? 0;

  // DELIBERATE: typed `true`, so the `{{#if}}` guarding it below can never be false.
  // The type-aware finding that has to land inside `<template>`.
  readonly isEnabled = true;

  increment = () => {
    this.count += this.args.step ?? 1;
  };

  <template>
    <div ...attributes>
      {{#if this.isEnabled}}
        <output>{{this.count}}</output>
      {{/if}}

      <button type="button" {{on "click" this.increment}}>Increment</button>

      {{yield this.count}}
      {{yield to="actions"}}
    </div>
  </template>
}
