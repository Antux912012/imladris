# Modern CSS3 Reference

Build adaptive stylesheets using CSS custom properties, `color-scheme: light dark`, tabular numerals, and `prefers-reduced-motion` media queries.

## Adaptive Nord Dark / Light Tokens & Motion Accessibility

```css
:root {
  color-scheme: light dark;
  --surface-bg: #f8fafc;
  --surface-fg: #1e242b;
  --accent-frost: #0284c7;
  --transition-fast: 160ms ease;
}

@media (prefers-color-scheme: dark) {
  :root {
    --surface-bg: #2e3440;
    --surface-fg: #eceff4;
    --accent-frost: #88c0d0;
  }
}

@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
  }
}

.metric-table td {
  font-variant-numeric: tabular-nums;
}
```
