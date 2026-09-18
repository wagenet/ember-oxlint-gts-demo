/** @type {import('@ember/component/template-only').TOC<{ Args: { alt: string; src: string } }>} */
const Avatar = <template>
  <img class="avatar" alt={{@alt}} src={{@src}} />
</template>;

export default Avatar;
