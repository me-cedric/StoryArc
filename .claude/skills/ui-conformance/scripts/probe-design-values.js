/*
 * Design-value probes for the ui-conformance skill, step 1.
 *
 * Paste one of these into Playwright's `browser_evaluate` against the running
 * app. They exist because fonts, colours and backgrounds are the checks a
 * screenshot cannot settle: a serif that should be sans, a #111827 that should
 * be #064e3b, and a gradient with the wrong stops all survive visual inspection
 * and die instantly against getComputedStyle.
 *
 * They also catch the failure no amount of code reading finds: a CSS Module
 * class overriding a utility class of equal specificity purely by source order.
 * The class is in the markup, the code reads correct, and the value is still
 * wrong — only the computed value tells you.
 *
 * Read the results against the Figma side (`get_design_context`,
 * `get_variable_defs`), and quote the measured value against the expected one in
 * the finding: "rgb(17,24,39) measured, expected #064e3b".
 */

/* ---------------------------------------------------------------------------
 * TYPOGRAPHY CENSUS — run this first.
 *
 * Groups every piece of visible text by (family, weight, size, line-height,
 * colour) and reports each combination with a sample and a count.
 *
 * The value is in what it finds unprompted: two spans of one heading that should
 * share a style show up as two rows, and a single hardcoded colour shows up as a
 * one-count row among a large one. You do not have to suspect a specific element
 * first, which is how this catches the bugs a targeted check would walk past.
 *
 * Hidden text is skipped on purpose — it is not what ships, and including it
 * turns the output into noise.
 * ------------------------------------------------------------------------- */
() => {
  const root = document.querySelector('main') || document.body;
  const seen = new Map();

  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
    acceptNode: (n) =>
      n.textContent.trim().length > 1 ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT,
  });

  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    const el = n.parentElement;
    if (!el) continue;
    const r = el.getBoundingClientRect();
    if (!r.width || !r.height) continue;

    const s = getComputedStyle(el);
    const key = [
      s.fontFamily.split(',')[0].replace(/"/g, ''),
      s.fontWeight,
      s.fontSize,
      s.lineHeight,
      s.color,
      // A gradient headline paints through its text, so `color` reads as
      // transparent; without this marker the row would look colourless rather
      // than gradient-filled.
      s.backgroundImage === 'none' ? '' : 'gradient-text',
    ].join(' | ');

    if (!seen.has(key)) {
      seen.set(key, {
        style: key,
        count: 0,
        sample: n.textContent.trim().slice(0, 60),
        tag: el.tagName.toLowerCase(),
        classes: el.className,
      });
    }
    seen.get(key).count++;
  }

  return [...seen.values()].sort((a, b) => b.count - a.count);
};

/* ---------------------------------------------------------------------------
 * TARGETED READ — once you know which elements the Figma node specifies.
 *
 * Swap the selector list for the elements under review. `backgroundImage` is
 * reported separately from `backgroundColor` because gradients live there, and
 * `box` gives the coordinates to quote in a dimension finding (add
 * window.scrollY for a position in the full page rather than the viewport).
 * ------------------------------------------------------------------------- */
() => {
  const SELECTORS = ['h1', 'h1 span', 'h2', '[class*="title"]', 'button'];
  const out = [];
  for (const sel of SELECTORS) {
    document.querySelectorAll(sel).forEach((el, i) => {
      const r = el.getBoundingClientRect();
      const s = getComputedStyle(el);
      out.push({
        sel: `${sel}[${i}]`,
        text: (el.textContent || '').trim().slice(0, 50),
        classes: el.className,
        box: {
          w: Math.round(r.width),
          h: Math.round(r.height),
          x: Math.round(r.x),
          y: Math.round(r.y + window.scrollY),
        },
        font: `${s.fontFamily.split(',')[0].replace(/"/g, '')} ${s.fontWeight} ${s.fontSize}/${s.lineHeight}`,
        color: s.color,
        background: s.backgroundColor,
        backgroundImage: s.backgroundImage === 'none' ? null : s.backgroundImage,
      });
    });
  }
  return out;
};

/* ---------------------------------------------------------------------------
 * BACKGROUND CHAIN — for "the page background does not match".
 *
 * A page background usually comes from an ancestor, and often from a ::before
 * layer rather than the element you suspect, so reading one node explains
 * nothing. This walks up and reports every painted layer, pseudo-elements
 * included.
 * ------------------------------------------------------------------------- */
() => {
  const out = [];
  let el = document.querySelector('main') || document.body;
  while (el) {
    const s = getComputedStyle(el);
    const before = getComputedStyle(el, '::before');
    const painted =
      s.backgroundColor !== 'rgba(0, 0, 0, 0)' ||
      s.backgroundImage !== 'none' ||
      before.backgroundImage !== 'none';
    if (painted) {
      out.push({
        node: `${el.tagName.toLowerCase()}.${String(el.className).split(' ').filter(Boolean).join('.')}`,
        backgroundColor: s.backgroundColor,
        backgroundImage: s.backgroundImage === 'none' ? null : s.backgroundImage.slice(0, 200),
        beforeImage: before.backgroundImage === 'none' ? null : before.backgroundImage.slice(0, 200),
      });
    }
    el = el.parentElement;
  }
  return out;
};
