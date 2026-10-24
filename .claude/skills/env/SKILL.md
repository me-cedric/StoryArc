---
name: env
description: Keep env vars in one catalog, one template and the code. Check them with ac env check, share secrets with age, start apps with ac env run. Use when you add, rename, read or share an env var.
risk_level: medium
writes_files: true
requires_tools: [ac, age]
---

# env

An env var has three homes: the catalog, the template and the code. Keep them equal.

## Rule

A new env var changes the catalog, the template and the code in one task.
A rename or a removal does the same. Then run `ac env check`.

## Catalog

`env.catalog.json` is at the project root. It is optional, but it makes `ac env check` strict.

```json
{
  "version": 1,
  "vars": [
    {
      "name": "LOG_LEVEL",
      "apps": ["api"],
      "description": "Log verbosity.",
      "default": "info",
      "example": "debug",
      "allowed": ["debug", "info", "warn"],
      "required": { "local": false, "ci": false, "staging": true, "prod": true }
    },
    { "name": "API_TOKEN", "secret": true, "pattern": "^[A-Za-z0-9_-]{20,}$", "required": { "local": true } }
  ]
}
```

- `name` is UPPER_SNAKE_CASE and is unique.
- Use `allowed` or `pattern`. Do not use both.
- `secret: true` marks a value that must never reach a client bundle.
- `required` has the keys `local`, `ci`, `staging` and `prod`.
- Put a placeholder in the template. Do not put a real value there.

## Check

```bash
ac env check          # one line for each finding
ac env check --json   # names, files and line numbers. Never a value.
```

Exit 1 means an error. A warning exits 0. Act on each finding:

| Finding | Meaning | Action |
|---|---|---|
| `catalog` | The catalog has a shape error. | Fix `env.catalog.json`. |
| `public-secret` | A name with a public prefix looks like a secret. The prefixes are `VITE_`, `NEXT_PUBLIC_`, `EXPO_PUBLIC_`, `REACT_APP_`, `NUXT_PUBLIC_` and `PUBLIC_`. | Remove the prefix. Read the value on the server. Rotate it if it shipped. |
| `undeclared` | Code reads a name that nothing declares. | Add the name to the catalog and the template. |
| `missing` | A required name has no value, or no template lists it. | Set the value in the local file. Or add the name to the template. |
| `unreadable` | A tracked env file is missing on disk, or it cannot be read. | Restore the file. Or remove it from git. |
| `extra` | A file holds a name that nothing declares. | Add the name to the catalog. Or delete it. |
| `invalid` | A local value breaks `allowed` or `pattern`. | Ask the owner for a valid value. |
| `overlap` | Two templates share names, and one folder holds the other. | Keep a shared name in the outer template only. |
| `duplicate` | Two nested templates list the same names. | Delete the inner template. |

Fix errors first. Then fix warnings in the same task, or write them down.

## Share a secret

Use `age` 1.3 or later and the SSH keys of the people. Never put a plain value in git, chat or a ticket.

```bash
ac env export --to alice,bob                        # keys from https://github.com/<user>.keys
ac env export --to alice --forge git.example.org    # a bare user on another forge
ac env export --to ./ci.pub --only API_TOKEN --out ci.age
ac env import env-bundle.age                        # identity: ~/.ssh/id_ed25519, then id_rsa
ac env import env-bundle.age --identity ~/.ssh/work_key --overwrite
```

- Export reads the local, git-ignored env files. It writes one encrypted `.age` file.
- Send the `.age` file by any channel. Only the listed recipients can open it.
- Import writes only git-ignored `.env*` files, with mode 0600. It refuses any other path and writes nothing then. It also refuses a value that a shell `source` can run.
- Import adds a missing name. It keeps a name that has another value. `--overwrite` replaces a one-line entry.

## Run with values

```bash
ac env run -- pnpm dev
ac env run --file .env.staging -- node scripts/seed.mjs
ac env run --bundle env-bundle.age -- pnpm dev      # the values stay in memory
```

`ac env run` loads `.env`, then `.env.local`. A name that the shell already has keeps the shell value.
The command starts without a shell. The values reach no file.

## Never read `.env` files

The guard hook blocks a read of any `.env*` file that is not a template.
To learn the names, read `env.catalog.json` or the template, or run `ac env check --json`.
To get a missing value, ask the user to set it in the local file or to import a bundle.

## TypeScript hosts with Zod 4

Keep the schema as the source. Put the catalog keys in `.meta()`.

```ts
export const envSchema = z.object({
  DATABASE_URL: z.url().meta({ description: 'Postgres URL.', apps: ['api'], secret: true, required: { ci: false } }),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn']).default('info').meta({ apps: ['api'] }),
})
```

1. Copy `assets/zod-catalog.mjs` from this skill folder into the host, for example to `scripts/zod-catalog.mjs`.
2. Run it with the host's own `zod` and `tsx`: `npx tsx scripts/zod-catalog.mjs src/env.ts envSchema`.
3. Commit the new `env.catalog.json`. Then run `ac env check`.

The script needs one `z.object({ ... })`. It maps `description`, `default`, `examples[0]`, `enum` and `pattern`.
It copies `apps`, `secret` and `required` from `.meta()`.
For a host without TypeScript, write `env.catalog.json` by hand.
