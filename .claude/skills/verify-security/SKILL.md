---
name: verify-security
description: Security verification gate. Scans code for vulnerabilities, detects dangerous patterns, and ensures security decisions are documented. Use when the user mentions security scans, vulnerability detection, security audits, code security, OWASP, injection detection, or sensitive-data leaks. Auto-triggers for new modules, security-related changes, offensive/defensive tasks, and completed refactors.
license: MIT
compatibility: node>=18
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash, Read, Grep
argument-hint: <scan-path>
risk_level: medium
writes_files: false
requires_tools: []
---

# ⚖ Verification Gate · Security

## Core principle

```
Security is the foundation; a breach sinks the release.
Security decisions must be traceable.
Critical/High findings must be fixed before delivery.
```

## Automatic scan

Run the security scanner script (cross-platform):

```bash
# from the skill directory
node scripts/security_scanner.cjs <scan-path>
node scripts/security_scanner.cjs <scan-path> -v           # verbose mode
node scripts/security_scanner.cjs <scan-path> --json       # JSON output
node scripts/security_scanner.cjs <scan-path> --exclude vendor  # exclude a directory
```

## Coverage

### Vulnerability classes detected

| Class | Checks | Severity |
|------|--------|--------|
| **Injection** | SQL injection, command injection, code injection | 🔴 Critical |
| **Secrets** | Hardcoded keys, AWS keys, private keys | 🔴 Critical |
| **XSS** | innerHTML, dangerouslySetInnerHTML | 🟠 High |
| **Deserialization** | pickle.loads, yaml.load | 🟠 High |
| **Path traversal** | Unvalidated file-path operations | 🟠 High |
| **SSRF** | Unvalidated URL requests | 🟠 High |
| **XXE** | Unsafe XML parsing | 🟠 High |
| **Weak crypto** | MD5/SHA1 in security contexts | 🟡 Medium |
| **Insecure randomness** | Non-crypto RNG in security contexts | 🟡 Medium |
| **Debug code** | console.log, print, debugger | 🔵 Low |

### Documentation-level checks

Security-relevant code must be recorded in DESIGN.md:

- [ ] **Threat model** — which attacks are defended against
- [ ] **Security decisions** — why this approach was chosen
- [ ] **Security boundaries** — where the trust boundaries sit
- [ ] **Accepted risks** — which risks were consciously accepted

## Dangerous-pattern quick reference

### Python
```python
# 🔴 Dangerous
eval(), exec(), os.system()
subprocess(..., shell=True)
pickle.loads(), yaml.load()
cursor.execute(f"SELECT * FROM t WHERE id = {id}")

# ✅ Safe alternative
ast.literal_eval()
subprocess([...], shell=False)
yaml.safe_load()
cursor.execute("SELECT * FROM t WHERE id = %s", (id,))
```

### JavaScript
```javascript
// 🔴 Dangerous
eval(), innerHTML, document.write()
new Function(userInput)

// ✅ Safe alternative
JSON.parse(), textContent
template engines with auto-escaping
```

### Go
```go
// 🔴 Dangerous
exec.Command("sh", "-c", userInput)
template.HTML(userInput)

// ✅ Safe alternative
exec.Command("cmd", args...)
html/template auto-escaping
```

## Verification flow

```
1. Run security_scanner.cjs
2. Review findings, sorted by severity
3. Check that security decisions are documented
4. Emit the security report
5. Critical/High findings must be fixed before delivery
```

## Auto-trigger moments

| Scenario | Trigger |
|------|----------|
| New module | When module creation completes |
| Security-related change | Auth, authorization, crypto, input handling |
| Offensive/defensive task | When a red/blue-team task completes |
| Refactor done | When a refactoring task completes |
| Pre-commit | Before committing code |

## Report format

```
## Security Verification Report

✓ pass | ✗ fail

- 🔴 Critical: N
- 🟠 High: N
- 🟡 Medium: N
- 🔵 Low: N

### Findings

| File | Line | Kind | Severity | Description |
|------|------|------|--------|------|
| ... | ... | ... | ... | ... |

### Verdict

Deliverable / fix before delivery
```

---
