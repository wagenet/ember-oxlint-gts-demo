import { module, test } from 'qunit';
import { click, render } from '@ember/test-helpers';

import { setupRenderingTest } from '../helpers/index.ts';
import Counter from '../../app/components/counter.gts';

module('Integration | Component | counter', function (hooks) {
  setupRenderingTest(hooks);

  test('it increments', async function (assert) {
    await render(
      <template>
        <Counter @start={{5}} @step={{3}} as |count|>
          <p data-test-yielded>{{count}}</p>
        </Counter>
      </template>,
    );

    assert.dom('output').hasText('5');

    await click('button');

    assert.dom('output').hasText('8');
    assert.dom('[data-test-yielded]').hasText('8');
  });
});
