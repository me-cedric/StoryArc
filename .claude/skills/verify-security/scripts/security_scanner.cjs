#!/usr/bin/env node
'use strict';

// security_scanner.cjs — security verification gate (see ../SKILL.md).
// Self-contained on purpose: skill folders are synced into hosts individually,
// so no cross-skill requires. CommonJS (.cjs) so it runs under any host
// package.json module type.

const fs = require('fs');
const path = require('path');

const SEVERITY_ORDER = { critical: 0, high: 1, medium: 2, low: 3, info: 4 };

// prettier-ignore
const SECURITY_RULES = [
  {
    id: 'SQL_INJECTION_DYNAMIC', category: 'injection',
    severity: 'critical',
    pattern: new RegExp(
      '\\b(execute|query|raw)\\s*\\(\\s*' +
      '(f["\']|["\'][^"\'\\n]*["\']\\s*\\+\\s*|["\'][^"\'\\n]*["\']\\s*%\\s*[^,)]|["\'][^"\'\\n]*["\']' +
      '\\.format\\s*\\()', 'i'),
    extensions: ['.py', '.js', '.ts', '.go', '.java', '.php'],
    message: 'Possible SQL injection',
    recommendation: 'Use parameterized queries or an ORM',
  },
  {
    id: 'SQL_INJECTION_FSTRING', category: 'injection',
    severity: 'critical',
    pattern: /cursor\.(execute|executemany)\s*\(\s*f["']/i,
    extensions: ['.py'],
    message: 'SQL statement built with an f-string',
    recommendation: 'Use parameterized queries',
  },
  {
    id: 'COMMAND_INJECTION', category: 'injection',
    severity: 'critical',
    pattern: /(os\.system|os\.popen|subprocess\.call|subprocess\.run|subprocess\.Popen)\s*\([^)]*shell\s*=\s*True/i,
    extensions: ['.py'],
    message: 'shell=True can allow command injection',
    recommendation: 'Avoid shell=True; pass arguments as a list',
  },
  {
    id: 'COMMAND_INJECTION_EVAL', category: 'injection',
    severity: 'critical',
    pattern: /\b(eval|exec)\s*\([^)]*\b(input|request|argv|args)/i,
    extensions: ['.py'],
    message: 'eval/exec on user input',
    recommendation: 'Never eval/exec user input',
  },
  {
    id: 'HARDCODED_SECRET', category: 'secrets',
    severity: 'high',
    pattern: /(?<!\w)(password|passwd|pwd|secret|api_key|apikey|token|auth_token)\s*=\s*["'][^"']{8,}["']/i,
    excludePattern: /(example|placeholder|changeme|xxx|your[_-]|TODO|FIXME|<.*>|\*{3,})/i,
    extensions: [
      '.py', '.js', '.ts', '.go', '.java', '.php',
      '.rb', '.yaml', '.yml', '.json', '.env',
    ],
    message: 'Possible hardcoded secret/password',
    recommendation: 'Use environment variables or a secret manager',
  },
  {
    id: 'HARDCODED_AWS_KEY', category: 'secrets',
    severity: 'critical',
    pattern: /AKIA[0-9A-Z]{16}/,
    extensions: ['*'],
    message: 'AWS access key found',
    recommendation: 'Rotate the key immediately; use IAM roles or environment variables',
  },
  {
    id: 'HARDCODED_PRIVATE_KEY', category: 'secrets',
    severity: 'critical',
    pattern: /-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----/,
    extensions: ['*'],
    message: 'Private key found',
    recommendation: 'Private keys must not be committed to the repository',
  },
  {
    id: 'XSS_INNERHTML', category: 'xss', severity: 'high',
    pattern: /\.innerHTML\s*=|\.outerHTML\s*=|document\.write\s*\(/i,
    extensions: ['.js', '.ts', '.jsx', '.tsx', '.html'],
    message: 'Direct innerHTML manipulation can allow XSS',
    recommendation: 'Use textContent or your framework\'s safe binding',
  },
  {
    id: 'XSS_DANGEROUSLY', category: 'xss',
    severity: 'medium',
    pattern: /dangerouslySetInnerHTML/i,
    extensions: ['.js', '.ts', '.jsx', '.tsx'],
    message: 'dangerouslySetInnerHTML in use',
    recommendation: 'Ensure the content is sanitized first',
  },
  {
    id: 'UNSAFE_PICKLE', category: 'deserialization',
    severity: 'high',
    pattern: /pickle\.loads?\s*\(|yaml\.load\s*\([^)]*Loader\s*=\s*yaml\.Loader/i,
    extensions: ['.py'],
    message: 'Unsafe deserialization',
    recommendation: 'Use yaml.safe_load() or validate the data source',
  },
  {
    id: 'WEAK_CRYPTO_MD5', category: 'crypto',
    severity: 'medium',
    pattern: /\b(md5|MD5)\s*\(|hashlib\.md5\s*\(/i,
    extensions: ['.py', '.js', '.ts', '.go', '.java', '.php'],
    message: 'Weak hash algorithm (MD5)',
    recommendation: 'Use bcrypt/argon2 for passwords, or SHA-256+',
  },
  {
    id: 'WEAK_CRYPTO_SHA1', category: 'crypto',
    severity: 'low',
    pattern: /\b(sha1|SHA1)\s*\(|hashlib\.sha1\s*\(/i,
    extensions: ['.py', '.js', '.ts', '.go', '.java', '.php'],
    message: 'Weak hash algorithm (SHA1)',
    recommendation: 'Use SHA-256 or stronger',
  },
  {
    id: 'PATH_TRAVERSAL', category: 'path-traversal',
    severity: 'high',
    pattern: new RegExp(
      '(open|read|write|Path|os\\.path\\.join)\\s*\\([^\\n]*' +
      '(request|input|argv|args|params|query|form|path_param)\\b', 'i'),
    extensions: ['.py'],
    message: 'Possible path traversal',
    recommendation: 'Validate and normalize user-supplied paths',
  },
  {
    id: 'SSRF', category: 'ssrf', severity: 'high',
    pattern: new RegExp(
      '(requests\\.(get|post|put|delete|head)|urllib\\.request\\.urlopen)' +
      '\\s*\\([^\\n]*(request|input|argv|args|params|query|url)\\b', 'i'),
    extensions: ['.py'],
    message: 'Possible SSRF',
    recommendation: 'Validate and restrict target URLs',
  },
  {
    id: 'DEBUG_CODE', category: 'debug', severity: 'low',
    pattern: /\b(console\.log|debugger|pdb\.set_trace|breakpoint)\s*\(/i,
    extensions: ['.py', '.js', '.ts'],
    message: 'Debug code found',
    recommendation: 'Remove debug code before production',
  },
  {
    id: 'INSECURE_RANDOM', category: 'crypto',
    severity: 'medium',
    pattern: /\brandom\.(random|randint|choice|shuffle)\s*\(/i,
    extensions: ['.py'],
    message: 'Insecure random number generator',
    recommendation: 'Use the secrets module in security contexts',
  },
  {
    id: 'XXE', category: 'xxe', severity: 'high',
    pattern: /etree\.(parse|fromstring)\s*\([^)]*\)|xml\.dom\.minidom\.parse/i,
    extensions: ['.py'],
    message: 'XML parsing may allow XXE',
    recommendation: 'Disable external entities: XMLParser(resolve_entities=False)',
  },
];

const CODE_EXTENSIONS = new Set([
  '.py', '.js', '.cjs', '.mjs', '.ts', '.jsx', '.tsx', '.go',
  '.java', '.php', '.rb', '.yaml', '.yml', '.json',
]);
const DEFAULT_EXCLUDES = [
  '.git', 'node_modules', '__pycache__', '.venv', 'venv',
  'dist', 'build', '.tox', 'tests', 'test', '__tests__', 'spec',
];

function scanFile(filePath, rules) {
  const findings = [];
  const ext = path.extname(filePath).toLowerCase();
  let content;
  try { content = fs.readFileSync(filePath, 'utf-8'); } catch { return findings; }
  const lines = content.split('\n');

  for (const rule of rules) {
    const exts = rule.extensions;
    if (!exts.includes('*') && !exts.includes(ext)) continue;

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const stripped = line.trim();
      const isComment = stripped.startsWith('#') ||
        stripped.startsWith('//') || stripped.startsWith('*') ||
        stripped.startsWith('/*');
      if (isComment) continue;
      const ruleDefRe = /^\s*(id|pattern|severity|message|recommendation|extensions|excludePattern|category)\s*:/;
      if (ruleDefRe.test(stripped)) continue;

      if (rule.pattern.test(line)) {
        rule.pattern.lastIndex = 0;
        if (rule.excludePattern && rule.excludePattern.test(line)) {
          rule.excludePattern.lastIndex = 0; continue;
        }
        findings.push({
          severity: rule.severity, category: rule.category,
          message: rule.message, file_path: filePath,
          line_number: i + 1,
          line_content: stripped.slice(0, 100),
          recommendation: rule.recommendation,
        });
      }
    }
  }
  return findings;
}

function walkDir(dir, excludeDirs) {
  const results = [];
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch { return results; }
  for (const entry of entries) {
    if (excludeDirs.includes(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) { results.push(...walkDir(full, excludeDirs)); }
    else if (entry.isFile()) {
      if (CODE_EXTENSIONS.has(path.extname(entry.name).toLowerCase())) {
        results.push(full);
      }
    }
  }
  return results;
}

function scanDirectory(scanPath, excludeDirs) {
  const resolved = path.resolve(scanPath);
  const findings = [];
  const files = walkDir(resolved, excludeDirs);
  for (const f of files) findings.push(...scanFile(f, SECURITY_RULES));
  findings.sort((a, b) =>
    (SEVERITY_ORDER[a.severity] ?? 9) - (SEVERITY_ORDER[b.severity] ?? 9));
  const passed = !findings.some(
    f => f.severity === 'critical' || f.severity === 'high'
  );
  return { scan_path: resolved, files_scanned: files.length, passed, findings };
}

// --- shared helpers (inlined; keep in sync across verify-* scripts) ---

function parseCliArgs(argv, extraFlags) {
  const args = argv.slice(2);
  const result = { target: '.', verbose: false, json: false };
  if (extraFlags) Object.assign(result, extraFlags);
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '-v' || args[i] === '--verbose') result.verbose = true;
    else if (args[i] === '--json') result.json = true;
    else if (args[i] === '-h' || args[i] === '--help') result.help = true;
    else if (args[i] === '--exclude') {
      result.exclude = result.exclude || [];
      while (i + 1 < args.length && !args[i + 1].startsWith('-')) result.exclude.push(args[++i]);
    } else if (!args[i].startsWith('-')) result.target = args[i];
  }
  return result;
}

const SEP = '='.repeat(60);
const DASH = '-'.repeat(40);
const ICONS = {
  error: '✗', warning: '⚠', info: 'ℹ',
  critical: '\u{1F534}', high: '\u{1F7E0}', medium: '\u{1F7E1}', low: '\u{1F535}',
};

function buildReport(title, fields, issues, verbose, groupBy) {
  const lines = [SEP, title, SEP];
  for (const [k, v] of Object.entries(fields)) lines.push(`\n${k}: ${v}`);
  if (issues.length) {
    lines.push('\n' + DASH, 'Findings:', DASH);
    if (groupBy) {
      const groups = {};
      for (const i of issues) (groups[i[groupBy]] || (groups[i[groupBy]] = [])).push(i);
      for (const cat of Object.keys(groups).sort()) {
        const items = groups[cat];
        lines.push(`\n[${cat}] (${items.length})`);
        for (const i of items.slice(0, 10)) {
          lines.push(`  ${ICONS[i.severity] || 'ℹ'} ${i.file_path || ''}${i.line_number ? ':' + i.line_number : ''}`);
          lines.push(`    ${i.message}`);
          if (verbose && i.recommendation) lines.push(`    💡 ${i.recommendation}`);
        }
        if (items.length > 10) lines.push(`  ... and ${items.length - 10} more`);
      }
    } else {
      for (const i of issues) lines.push(`  ${ICONS[i.severity] || 'ℹ'} [${i.severity.toUpperCase()}] ${i.message}`);
    }
  }
  lines.push('\n' + SEP);
  return lines.join('\n');
}

function countBySeverity(issues, field) {
  const key = field || 'severity';
  const counts = {};
  for (const i of issues) counts[i[key]] = (counts[i[key]] || 0) + 1;
  return counts;
}

function formatReport(result, verbose) {
  const counts = countBySeverity(result.findings);
  const fields = {
    'Scan path': result.scan_path,
    'Files scanned': result.files_scanned,
    'Result': result.passed ? '✓ pass' : '✗ high-severity findings',
    'Counts': `critical: ${counts.critical || 0} | high: ${counts.high || 0}` +
      ` | medium: ${counts.medium || 0} | low: ${counts.low || 0}`,
  };
  return buildReport(
    'Security Scan Report', fields, result.findings, verbose, 'category'
  );
}

function main() {
  const opts = parseCliArgs(process.argv, { exclude: [] });
  if (opts.help) {
    console.log('Usage: security_scanner.cjs [path] [-v] [--json] [--exclude dir1 dir2]');
    process.exit(0);
  }
  const excludeDirs = [...DEFAULT_EXCLUDES, ...opts.exclude];
  const result = scanDirectory(opts.target, excludeDirs);

  if (opts.json) {
    console.log(JSON.stringify({
      scan_path: result.scan_path,
      files_scanned: result.files_scanned,
      passed: result.passed,
      counts: countBySeverity(result.findings),
      findings: result.findings,
    }, null, 2));
  } else {
    console.log(formatReport(result, opts.verbose));
  }
  process.exit(result.passed ? 0 : 1);
}

if (require.main === module) {
  main();
}

module.exports = { scanFile, SECURITY_RULES };
