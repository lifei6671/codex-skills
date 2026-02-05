---
name: github-project-share
description: Generate Chinese share articles for GitHub open-source projects. Trigger when the user provides a GitHub repository URL (e.g., https://github.com/shadcn-ui/ui) and wants an article based on README and official docs, including preface with greeting + project summary + docs link (if any), project preview with screenshots and usage, project highlights, deployment tutorial with pitfalls, and a closing summary. Requires web.run to fetch README/docs and cite sources.
---

# GitHub Project Share

## Overview

Create a Chinese share article for a GitHub project using the README and official documentation. The output must follow the exact section order and format in `references/article-template.md`.

## Workflow

1. Parse the GitHub repo URL from the user input. The trigger is the GitHub URL itself.
2. Use `web.run` to fetch:
   - README content (primary source).
   - Official documentation (from README links or repo website).
   - Screenshots/images referenced in README/docs.
3. Extract:
   - Project summary, core features, and usage.
   - Installation/deployment steps and configuration.
   - Notable pitfalls or gotchas from docs/issues/FAQ.
4. Generate the article using the template and keep sections in the required order.
5. Add citations for all factual statements and any paraphrased doc content.

## Output Rules

- Language: Chinese only.
- Use the template in `references/article-template.md` verbatim for section titles.
- Only use screenshots found in README/official docs. Do NOT use GitHub OpenGraph images.
- Links must be wrapped in inline code (e.g., `https://example.com`) to avoid raw URLs.
- If no screenshot is found, write "未找到截图" and continue.
- If official docs are not found, say so and use README as the primary source.
- If deployment steps are not documented, state the gap explicitly and provide the safest minimal steps from README only.

## Quality Checklist

- All sections present and in order.
- Preface includes greeting, short summary, and docs link (if any).
- Project Preview includes at least one screenshot (or explicit absence) and usage instructions.
- Highlights are concrete and specific, not generic praise.
- Deployment includes step-by-step instructions plus pitfalls.
- Summary is concise and closes the article.
- Citations included throughout.

## Resources

- `references/article-template.md`: Required output structure.
