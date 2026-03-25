# CSS Migration Guide - How to Use the New Unified System

## Quick Start

The CSS has been completely restructured. Here's what you need to know:

## ✅ What Changed

### Before (Broken)
```scss
// Old way - caused errors
$haitian-blue: var(--haitian-blue, #00209F);  // ❌ Bootstrap couldn't compile this

// Multiple files importing tokens
@use "../base/tokens" as *;  // ❌ Caused variable conflicts
```

### After (Fixed)
```scss
// New way - works everywhere
$haitian-blue: #00209F;  // ✅ Actual SCSS value

// Tokens loaded globally - no need to import
// Just use the variables directly
.my-component {
  color: $haitian-blue;  // ✅ Works!
}
```

## 📋 Developer Quick Reference

### Using Colors

```scss
// In SCSS files
.button {
  background: $haitian-blue;      // Primary brand color
  color: $white;                   // White text
  border: 1px solid $mid-gray;    // Border

  &:hover {
    background: $ocean-blue;       // Lighter blue
  }
}

// In HTML/CSS (runtime)
<div style="background: var(--haitian-blue)">
  Using CSS custom property
</div>
```

### Using Typography

```scss
.heading {
  font-family: $font-heading;  // Montserrat, Inter
}

.body-text {
  font-family: $font-body;     // Inter, Montserrat
}
```

### Using Spacing & Radii

```scss
.card {
  border-radius: $radius-lg;   // 1.3rem (large)
  border-radius: $radius-md;   // 0.75rem (medium)
  border-radius: $radius-sm;   // 0.45rem (small)
}
```

### Using Shadows

```scss
.elevated-card {
  box-shadow: $shadow-soft;     // Subtle elevation
  box-shadow: $shadow-card;     // Strong card shadow
  box-shadow: $shadow-glow-blue; // Haitian blue glow
}
```

## 🎨 Complete Token Reference

### Brand Colors
| Variable | Value | Usage |
|----------|-------|-------|
| `$haitian-blue` | #00209F | Primary brand, buttons, headers |
| `$haitian-red` | #E53E3E | Danger states, alerts |
| `$ocean-blue` | #3366CC | Links, info states |
| `$palm-green` | #1A936F | Success states |
| `$golden-yellow` | #EDB95E | Warnings, highlights |
| `$haitian-cyan` | #00E4FF | Accents, hover states |

### Neutrals
| Variable | Value | Usage |
|----------|-------|-------|
| `$white` / `$pure-white` | #FFFFFF | Backgrounds, text on dark |
| `$offwhite` | #F7F7F9 | Card backgrounds |
| `$light-gray` | #F8F9FA | Page backgrounds |
| `$mid-gray` | #6C757D | Secondary text, borders |
| `$dark-gray` | #343A40 | Primary text |
| `$gray-900` | #212529 | Darkest text |

### Bootstrap Grays (for forms, borders)
| Variable | Value |
|----------|-------|
| `$gray-100` | #f8f9fa |
| `$gray-200` | #e9ecef |
| `$gray-300` | #dee2e6 |
| `$gray-400` | #ced4da |
| `$gray-500` | #adb5bd |
| `$gray-600` | #6c757d |
| `$gray-700` | #495057 |
| `$gray-800` | #343a40 |

## 📁 File Structure

### Shared Across All Layouts (Public/Admin/Citizen)

```
app/assets/stylesheets/
├── application.scss          ← Main entry point
├── base/
│   ├── _tokens.scss         ← ✨ ALL design tokens (colors, fonts, etc.)
│   ├── _reset.scss          ← CSS reset
│   └── _base.scss           ← Foundation styles
├── admin/                   ← Admin-specific
├── citizens/                ← Citizen-specific
├── components/              ← Shared UI components
├── shared/                  ← Shared partials
├── partners/                ← Partner portal
└── main/                    ← Public pages
```

### Isolated Stylesheets (Don't Touch Unless Working on Those Areas)

```
app/assets/stylesheets/
├── officer.scss             ← Law enforcement (isolated)
├── officers/                ← Officer styles
├── visitor.scss             ← Tourists/visitors (isolated)
└── visitor/                 ← Visitor styles
```

## 🚀 Creating New Components

### Example: New Card Component

**File**: `app/assets/stylesheets/components/_my_card.scss`

```scss
// No need to @import or @use tokens - they're already global!

.my-card {
  background: $white;
  border-radius: $radius-lg;
  box-shadow: $shadow-card;
  padding: 2rem;
  border: 1px solid $gray-300;

  &__header {
    font-family: $font-heading;
    color: $haitian-blue;
    font-size: 1.5rem;
    margin-bottom: 1rem;
  }

  &__body {
    font-family: $font-body;
    color: $dark-gray;
    line-height: 1.6;
  }

  &:hover {
    box-shadow: $shadow-glow-blue;
    transform: translateY(-2px);
    transition: all 0.3s ease;
  }
}
```

**Then add to `application.scss`**:

```scss
// In application.scss
@import "components/my_card";
```

## 🎯 Layout-Specific Styling

### For Public Pages Only

```scss
// In main/my_page.scss
body.public-app {
  .special-hero {
    background: linear-gradient(135deg, $haitian-blue, $ocean-blue);
  }
}
```

### For Admin Only

```scss
// In admin/my_component.scss
body.admin-layout {
  .admin-widget {
    border-left: 4px solid $haitian-blue;
  }
}
```

### For Citizen Only

```scss
// In citizens/my_feature.scss
body.citizen-app {
  .citizen-badge {
    background: $palm-green;
    color: $white;
  }
}
```

## ⚠️ Common Mistakes to Avoid

### ❌ DON'T: Import tokens in component files
```scss
// ❌ WRONG - This causes conflicts!
@use "../base/tokens" as *;
@import "../base/tokens";

.my-component { ... }
```

### ✅ DO: Use tokens directly
```scss
// ✅ CORRECT - Tokens are already global
.my-component {
  color: $haitian-blue;
}
```

### ❌ DON'T: Use var() with SCSS functions
```scss
// ❌ WRONG - Bootstrap can't compile this
$my-color: var(--haitian-blue);
background: lighten($my-color, 10%);  // Error!
```

### ✅ DO: Use SCSS variables with functions
```scss
// ✅ CORRECT
background: lighten($haitian-blue, 10%);  // Works!
```

### ❌ DON'T: Create duplicate color variables
```scss
// ❌ WRONG - Use tokens instead
$my-blue: #00209F;  // This already exists as $haitian-blue!
```

### ✅ DO: Reuse existing tokens
```scss
// ✅ CORRECT
.my-element {
  color: $haitian-blue;  // Use existing token
}
```

## 🧪 Testing Your Styles

### 1. Compile and Check for Errors
```bash
bin/rails assets:precompile
# Should complete without errors
```

### 2. Check Compiled CSS Size
```bash
ls -lh app/assets/builds/application.css
# Should be ~395KB
```

### 3. Test in Browser
```bash
bin/rails server
# Visit http://localhost:3000
# Open DevTools → Elements → Computed
# Check that CSS custom properties are available
```

### 4. Verify Tokens in Console
```javascript
// In browser console
getComputedStyle(document.documentElement).getPropertyValue('--haitian-blue')
// Should output: " #00209F"

getComputedStyle(document.documentElement).getPropertyValue('--font-body')
// Should output: " "Inter", "Montserrat", sans-serif"
```

## 📊 Before vs After Comparison

| Aspect | Before (Broken) | After (Fixed) |
|--------|----------------|---------------|
| **Token Definition** | CSS vars only, no values | CSS vars + SCSS vars with values |
| **Import Method** | Multiple `@use` imports | Global via `application.scss` |
| **Bootstrap Compat** | ❌ Broken | ✅ Works perfectly |
| **Compilation** | ❌ Errors | ✅ Clean compile |
| **File Size** | 922 bytes (error) | 395KB (correct) |
| **Admin Layout** | ❌ Broken | ✅ Working |
| **Citizen Layout** | ❌ Broken | ✅ Working |
| **Root/Public** | ❌ Broken | ✅ Working |

## 🔧 Troubleshooting

### "Undefined variable $haitian-blue"
**Cause**: Component file is compiled before `application.scss`
**Fix**: Make sure your file is imported AFTER `base/tokens` in `application.scss`

### "This module and the new module both define a variable"
**Cause**: File has `@use "../base/tokens"` when tokens are already global
**Fix**: Remove the `@use` statement - tokens are already available

### "Bootstrap compilation error"
**Cause**: Using `var()` in SCSS variable
**Fix**: Use actual color values in `base/_tokens.scss`, not `var()` wrappers

### CSS not updating
**Cause**: Cached assets
**Fix**:
```bash
rm -rf app/assets/builds/*
bin/rails assets:precompile
```

## 📚 Additional Resources

- **Design Tokens**: `app/assets/stylesheets/base/_tokens.scss`
- **Foundation Styles**: `app/assets/stylesheets/base/_base.scss`
- **Full Fix Documentation**: `CSS_FIX_SUMMARY.md`
- **Bootstrap Docs**: https://getbootstrap.com/docs/5.3/

## 🎉 Summary

You now have:
- ✅ A unified design system with CSS custom properties + SCSS variables
- ✅ Bootstrap integration that actually works
- ✅ Global tokens accessible everywhere (no imports needed)
- ✅ Clean separation between shared (Public/Admin/Citizen) and isolated (Officers/Visitors) styles
- ✅ Consistent Haitian branding across all layouts

**Just use the tokens directly in your SCSS - they're already loaded globally!**
