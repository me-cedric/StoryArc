---
agent: agent
description: Turn a rough request into a stronger agent prompt.
---

Rewrite this request into a precise agent prompt:

${input:request:Paste the rough request}

Return:

```text
Goal:
Context:
Constraints:
Done when:
Validation:
```

Then add:

- One reason this prompt is stronger.
- One provider-native tool to consider, only if it clearly fits.
