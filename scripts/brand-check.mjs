// `pnpm brand:check`, which pnpm runs through cmd.exe on Windows, so it cannot be a shell `if`.
// The generator imports CoreGraphics and ImageIO, which exist only on Apple platforms.
import { spawnSync } from 'node:child_process'

if (process.platform !== 'darwin') {
  console.log('brand:check: skipped. The generator imports CoreGraphics and ImageIO, which exist only on Apple platforms. The iOS workflow runs it on macOS.')
  process.exit(0)
}
const run = spawnSync('swift', ['scripts/brand-mark.swift', '--out', '.', '--check'], { stdio: 'inherit' })
process.exit(run.status ?? 1)
