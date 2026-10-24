// eslint-boundaries.mjs — atomic design gate for eslint-plugin-boundaries 7. Copy it next to eslint.config.mjs.
//   import atomic from './eslint-boundaries.mjs'
//   export default [...yourConfig, ...atomic]
// A level imports only lower levels: a molecule can use an atom, an atom cannot use a molecule.
// Imports inside one level, from shared code and from packages stay allowed.
// Edit ROOT when the components are in another folder.

import boundaries from 'eslint-plugin-boundaries'

const ROOT = 'src/components'
const LEVELS = ['atoms', 'molecules', 'organisms', 'templates', 'pages']

export default [
  {
    files: ['**/*.{js,jsx,ts,tsx}'],
    plugins: { boundaries },
    settings: {
      'boundaries/elements': LEVELS.map((type) => ({ type, pattern: `${ROOT}/${type}` })),
    },
    rules: {
      'boundaries/dependencies': ['error', {
        default: 'allow',
        policies: LEVELS.slice(0, -1).map((type, i) => ({
          from: { element: { type } },
          disallow: { to: { element: { type: LEVELS.slice(i + 1) } } },
        })),
      }],
    },
  },
]
