export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // Scopes name the area a change lands in, so the log reads as a map of the
    // repository rather than a list of verbs.
    'scope-enum': [
      2,
      'always',
      ['ios', 'android', 'desktop', 'tokens', 'specs', 'docs', 'ci', 'repo', 'fixtures'],
    ],
    'scope-empty': [1, 'never'],
    'body-max-line-length': [1, 'always', 100],
  },
}
