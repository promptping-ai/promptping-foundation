# Implementation Plans

This document links to implementation plans for features and improvements.

## Active Plans

### 1. Reply/Resolve MVP (1-Hour Implementation)
**Plan:** `~/.claude/plans/cozy-orbiting-puppy.md`  
**Status:** Ready for Opus burst session  
**Scope:**
- Fix MarkdownPreserver index synchronization bug (critical!)
- Add reply-to and resolve subcommands (GitLab/Azure only)
- Expose comment/thread IDs in formatter
- Translation integration

**Time Estimate:** 60 minutes  
**Hand-off:** Opus agent

### 2. Advanced Features (Post-MVP)
**Plan:** `~/.claude/plans/pr-comments-advanced-features.md`  
**Status:** Planned for future sprints  
**Features:**
- Foundation Models summarization & actionable extraction
- Comment filtering (unresolved, since timestamp, actionable-only)
- Code visualization with suggested fixes
- Pipeline checks watch tool (separate CLI)
- Status bar integration (macOS menubar app)

## Completed Work

### Translation with Markdown Preservation
**Plan:** `~/.claude/plans/sequential-hugging-cray.md`  
**Status:** ✅ Complete  
**Branch:** `promptping-ai-translation-chunking`  
**PR:** #49

- Translation.framework integration (21 languages)
- swift-markdown AST-based preservation
- No regex, no placeholders - proper AST walking
- All tests passing (51/51)
