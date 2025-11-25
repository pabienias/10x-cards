# 10xCards

Fast, AI‑assisted flashcard creation and learning with spaced repetition (SRS). Paste any text (1–10k chars) and get up to 10 concise Q/A cards, then learn them with a proven SRS flow.

## Table of contents
- [1. Project name](#1-project-name)
- [2. Project description](#2-project-description)
- [3. Tech stack](#3-tech-stack)
- [4. Getting started locally](#4-getting-started-locally)
- [5. Available scripts](#5-available-scripts)
- [6. Project scope](#6-project-scope)
- [7. Project status](#7-project-status)
- [8. License](#8-license)

## 1. Project name
10xCards

## 2. Project description
10xCards is a web app that minimizes the time and effort needed to create high‑quality flashcards by:
- generating up to 10 Q/A cards from pasted text in the same language as the input,
- letting users accept, edit, or reject each candidate before saving,
- providing a learning screen powered by a standard open‑source SRS library.

Key goals:
- Reduce friction of preparing study materials.
- Encourage adoption of SRS by making card creation fast and simple.
- Keep costs predictable via daily token limits and an economical fallback mode.

For full product requirements, see the PRD: `.ai/prd.md`.

## 3. Tech stack
- Frontend: Next.js 16, React 19, TypeScript 5, Tailwind CSS 4, shadcn/ui
- Backend/Persistence: Supabase (auth, Postgres, RLS)
- AI Integration: OpenAI SDK
- CI/CD & Hosting: GitHub Actions, Vercel

Details: `.ai/tech-stack.md`

## 4. Getting started locally
Prerequisites:
- Node.js v20.11.0 (see `.nvmrc`)
- npm, pnpm, or yarn

Recommended:
```bash
nvm use
```

Install dependencies and run the dev server:
```bash
# install
npm install

# start dev server
npm run dev
```

Visit http://localhost:3000

Project structure highlights:
- `src/app/` — Next.js routes and layouts
- `src/components/` — reusable UI components
- `src/app/api/` — API route handlers
- `src/utils/` — small, stateless utilities
- `public/` — static assets

## 5. Available scripts
From `package.json`:
- `dev`: start the Next.js development server
- `build`: build the production bundle
- `start`: start the production server (after `build`)
- `lint`: run ESLint

## 6. Project scope
In scope (MVP):
- AI generation of up to 10 Q/A cards from pasted text (1–10k chars), text‑only.
- Manual card creation with character limits (front ≤ 200, back ≤ 500).
- Accept/edit/reject AI candidates; only accepted cards are saved.
- Auth via Supabase; full features gated to signed‑in users.
- SRS learning flow with 4‑point grading: Again, Hard, Good, Easy.
- Performance and cost controls: daily token limit per user, economical fallback.

Out of scope (MVP):
- Custom/tuned SRS algorithm beyond the chosen library's defaults.
- Importing files (PDF, DOCX, etc.).
- Sharing/collaboration features.
- Mobile apps; web only.
- Tag/collection search and advanced organization.

Full details and acceptance criteria: `.ai/prd.md`

## 7. Project status
- Stage: MVP under active development
- Team: 1 person
- Target: ~3 weeks to MVP

See `.ai/prd.md` for user stories and performance goals.

## 8. License
No license specified yet. If you plan to use or distribute this code, please add a LICENSE file and update this section accordingly.
