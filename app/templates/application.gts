import { pageTitle } from 'ember-page-title';

import { Avatar, Banner, Counter, Greeting } from '../components/index.ts';

<template>
  {{pageTitle "oxlint gts demo"}}

  <main>
    <Banner />
    <Greeting @first="Ada" @last="Lovelace" />
    <Avatar @alt="Ada Lovelace" @src="/robots.txt" />

    <Counter @start={{1}} @step={{2}} as |count|>
      <p>count is {{count}}</p>
    </Counter>
  </main>

  {{outlet}}
</template>
