# Production Review Checklist

Run through the production checklist interactively.

## Step 1: Load Checklist

Read `docs/30_production-checklist.md` to get the checklist items.

If it doesn't exist, use this default checklist:

```
## Code Quality
- [ ] No compiler warnings
- [ ] No force unwraps in production code
- [ ] Error handling is comprehensive
- [ ] No hardcoded secrets or API keys

## User Experience
- [ ] Loading states for async operations
- [ ] Error messages are user-friendly
- [ ] Empty states are handled
- [ ] Accessibility labels on interactive elements

## Testing
- [ ] Core user flows tested manually
- [ ] Edge cases considered
- [ ] Different screen sizes tested (if applicable)

## Performance
- [ ] No obvious memory leaks
- [ ] Reasonable launch time
- [ ] Smooth scrolling/animations

## Release Prep
- [ ] Version number updated
- [ ] Release notes drafted
- [ ] Screenshots updated (if App Store)
```

## Step 2: Interactive Review

Go through each section, asking:

"**[Section Name]** - Ready to review this section?"

For each item:
- Ask "✓ [Item]?"
- User confirms or flags issue
- If issue flagged, note it

## Step 3: Generate Report

Create a summary:

```markdown
## Production Review: YYYY-MM-DD

### Passed
- [x] Item 1
- [x] Item 2

### Issues Found
- [ ] Item 3 - [note about issue]
- [ ] Item 4 - [note about issue]

### Summary
X of Y items passed. [Ready to ship / Issues need addressing]
```

## Step 4: Save or Display

Ask: "Save this report to docs/sessions/review-YYYY-MM-DD.md?"

If yes, save it. Either way, display the summary.
