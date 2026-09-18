import Component from '@glimmer/component';
import { on } from '@ember/modifier';

export interface SaveButtonSignature {
  Args: {
    save: () => Promise<void>;
  };
  Element: HTMLButtonElement;
}

export default class SaveButton extends Component<SaveButtonSignature> {
  // DELIBERATE: the promise is never awaited or caught, so `no-floating-promises`
  // reports here. A type-aware finding in the script half of the same file.
  handleClick = () => {
    this.args.save();
  };

  <template>
    <button
      type="button"
      ...attributes
      {{on "click" this.handleClick}}
    >Save</button>
  </template>
}
