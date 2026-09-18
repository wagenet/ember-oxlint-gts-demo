import type { TOC } from '@ember/component/template-only';

import { formatName } from '../helpers/format.ts';

export interface GreetingSignature {
  Args: {
    first: string;
    last: string;
  };
  Element: HTMLParagraphElement;
}

// `formatName` is referenced ONLY from the template. Nothing reports it as unused:
// the template is part of the source oxlint sees.
export const Greeting: TOC<GreetingSignature> = <template>
  <p ...attributes>Hello, {{formatName @first @last}}</p>
</template>;

export default Greeting;
