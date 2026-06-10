import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join, dirname } from "node:path"
import { mkdir, access, readdir, readFile, writeFile, unlink } from "node:fs/promises"

// Paths relative to project directory
const PERSONAL_NOTES = ".opencode/personal.md"
const FROM_CLAUDE = ".opencode/from-claude.md"
const CC_MEMORY_POINTER = ".opencode/.cc-memory-path"
const PLUGIN_FILE = ".opencode/plugin/memory-bridge-opencode.ts"
// OpenCode's "beast" system prompt (default for GPT/o-series models) tells the
// model to store memories at the VS Code Copilot convention path below. We
// can't out-prompt a system message, so we absorb that path as a second source.
const BEAST_MEMORY = ".github/instructions/memory.instruction.md"

// Header injected into personal.md so OpenCode knows where to write memories
const PERSONAL_HEADER =
  "<!-- memory-bridge-opencode: this file is your project-scoped personal memory.\n" +
  "     When asked to remember something for this project, append it to THIS\n" +
  "     file (.opencode/personal.md) as a short plain bullet.\n" +
  "     Synced to Claude Code memory on each turn. -->\n\n"

// Feature 1: ensure opencode.json + .gitignore are set up
async function ensureSetup(directory: string): Promise<void> {
  // opencode.json — add personal.md + from-claude.md to instructions if missing
  const ocJsonPath = join(directory, "opencode.json")
  let cfg: Record<string, unknown> = {}
  try { cfg = JSON.parse(await readFile(ocJsonPath, "utf8")) } catch { /* new file */ }
  const existing: string[] = Array.isArray(cfg.instructions) ? (cfg.instructions as string[]) : []
  const toAdd = [PERSONAL_NOTES, FROM_CLAUDE].filter(e => !existing.includes(e))
  if (toAdd.length) {
    cfg.instructions = [...existing, ...toAdd]
    await writeFile(ocJsonPath, JSON.stringify(cfg, null, 2) + "\n")
    console.error(`[memory-bridge-opencode] opencode.json: added instructions ${toAdd.join(", ")}`)
  }

  // .gitignore — add entries not already covered by an existing pattern
  const gitignorePath = join(directory, ".gitignore")
  let gi = ""
  try { gi = await readFile(gitignorePath, "utf8") } catch { /* new file */ }
  const giLines = gi.split("\n")

  function isCovered(entry: string): boolean {
    if (giLines.includes(entry)) return true
    // ".opencode/" covers ".opencode/personal.md" etc.
    const parts = entry.split("/")
    for (let i = 1; i < parts.length; i++) {
      if (giLines.includes(parts.slice(0, i).join("/") + "/")) return true
    }
    return false
  }

  const missing = [PERSONAL_NOTES, FROM_CLAUDE, CC_MEMORY_POINTER, PLUGIN_FILE].filter(
    e => !isCovered(e),
  )
  if (missing.length) {
    const newGi = gi.trimEnd() + "\n" + missing.join("\n") + "\n"
    await writeFile(gitignorePath, newGi)
    console.error(`[memory-bridge-opencode] .gitignore: added ${missing.join(", ")}`)
  }
}

// Feature 2: ensure personal.md has the memory-guide header
async function ensurePersonalMd(directory: string): Promise<void> {
  const path = join(directory, ".opencode", "personal.md")
  let content = ""
  try { content = await readFile(path, "utf8") } catch { /* doesn't exist yet */ }
  if (!content.startsWith("<!--")) {
    await mkdir(dirname(path), { recursive: true })
    await writeFile(path, PERSONAL_HEADER + content)
    console.error("[memory-bridge-opencode] personal.md: added memory-guide header")
  }
}

// Feature 2.5: relocate stray beast-prompt memories into personal.md.
// GPT/o-series models follow their system prompt ("beast") and write memories
// to .github/instructions/memory.instruction.md no matter what our guide says.
// We can't out-prompt a system message — so on every sync we sweep that path:
// move its content into the canonical personal.md (dedup-guarded, so reruns
// are safe), then delete the stray file to keep the project clean.
async function relocateBeastNotes(directory: string): Promise<void> {
  const strayPath = join(directory, BEAST_MEMORY)
  let raw = ""
  try { raw = await readFile(strayPath, "utf8") } catch { return }  // no stray file — done

  const body = raw
    .replace(/^---\n[\s\S]*?\n---\n?/, "")   // strip beast-style frontmatter
    .trim()

  const personalPath = join(directory, PERSONAL_NOTES)
  let personal = ""
  try { personal = await readFile(personalPath, "utf8") } catch { /* will create below */ }

  if (body && !personal.includes(body)) {
    const base = personal.trimEnd() || PERSONAL_HEADER.trimEnd()
    await mkdir(dirname(personalPath), { recursive: true })
    await writeFile(personalPath, base + "\n\n" + body + "\n")
    console.error(`[memory-bridge-opencode] relocated stray memory: ${BEAST_MEMORY} -> ${PERSONAL_NOTES}`)
  }
  try {
    await unlink(strayPath)
    console.error(`[memory-bridge-opencode] removed ${BEAST_MEMORY}`)
  } catch { /* deletion failed — the merge fallback below still picks it up */ }
}

// Feature 3: sync OpenCode-side notes → CC memory/from-opencode.md
// Primary source: .opencode/personal.md (canonical — beast strays are
// relocated into it above). BEAST_MEMORY is read here only as a failure-mode
// fallback (e.g. relocation's delete failed mid-flight).
async function collectNotes(directory: string): Promise<string> {
  const parts: string[] = []
  for (const rel of [PERSONAL_NOTES, BEAST_MEMORY]) {
    let text = ""
    try { text = await readFile(join(directory, rel), "utf8") } catch { continue }
    text = text
      .replace(/^---\n[\s\S]*?\n---\n?/, "")        // strip leading frontmatter (beast format)
      .replace(/^<!--[\s\S]*?-->\s*/, "")           // strip our guide header comment
      .trim()
    if (text) parts.push(`<!-- source: ${rel} -->\n${text}`)
  }
  return parts.join("\n\n")
}

// Resolve this project's CC memory directory: exact pointer written by the CC
// hook when available, else probe known CC data dirs (production first).
async function resolveCCMemoryDir(directory: string): Promise<string> {
  // Plan B: read exact CC memory path from pointer file written by memory-bridge.sh
  try {
    const ptr = (await readFile(join(directory, CC_MEMORY_POINTER), "utf8")).trim()
    if (ptr) {
      console.error(`[memory-bridge-opencode] cc_home from pointer: ${ptr}`)
      return ptr
    }
  } catch { /* pointer not written yet — CC session hasn't run */ }

  // Fallback: probe CC data dirs — CLAUDE_CONFIG_DIR (production relocation
  // var, if set) > ~/.claude (production default) > ~/.claude-fork (dev).
  const slug = directory.replace(/[^A-Za-z0-9]/g, "-")
  const bases = [
    ...(process.env.CLAUDE_CONFIG_DIR ? [process.env.CLAUDE_CONFIG_DIR] : []),
    join(homedir(), ".claude"),
    join(homedir(), ".claude-fork"),
  ]
  const candidates = bases.map(b => join(b, "projects", slug, "memory"))
  for (const candidate of candidates) {
    try {
      await access(candidate)
      console.error(`[memory-bridge-opencode] cc_home from fallback-probe: ${candidate}`)
      return candidate
    } catch { /* try next */ }
  }
  console.error(`[memory-bridge-opencode] cc_home defaulting to: ${candidates[0]}`)
  return candidates[0]  // none exist yet -> production default
}

// Feature 1.7: bootstrap from-claude.md when it is missing.
// Owner of that file is the CC hook (memory-bridge-claude), which rewrites it
// wholesale on every turn/session — but until any Claude session has run here
// (fresh clone, wiped .opencode/, CC plugin not yet installed) the file simply
// doesn't exist and OpenCode reads nothing. If we can see this project's CC
// memory, flatten it once ourselves. Never overwrites an existing file.
async function bootstrapFromClaude(directory: string): Promise<void> {
  const target = join(directory, FROM_CLAUDE)
  try { await access(target); return } catch { /* missing — bootstrap it */ }

  const ccMemoryDir = await resolveCCMemoryDir(directory)
  let entries: string[] = []
  try { entries = await readdir(ccMemoryDir) } catch { /* no CC memory dir yet */ }
  const files = entries
    .filter(f => f.endsWith(".md") && f !== "MEMORY.md" && f !== "from-opencode.md") // echo guard 유지
    .sort()

  const parts: string[] = []
  for (const f of files) {
    try { parts.push((await readFile(join(ccMemoryDir, f), "utf8")).trimEnd()) } catch { /* skip unreadable */ }
  }

  const header =
    `<!-- Bootstrapped by memory-bridge-opencode from ${ccMemoryDir}.\n` +
    `     The Claude Code hook (memory-bridge-claude) overwrites this file\n` +
    `     whenever a Claude Code session runs in this project. -->\n\n`
  const body = parts.length
    ? parts.join("\n\n") + "\n"
    : "<!-- No Claude Code memory found for this project yet. -->\n"
  await mkdir(dirname(target), { recursive: true })
  await writeFile(target, header + body)
  console.error(`[memory-bridge-opencode] bootstrapped ${FROM_CLAUDE} (${parts.length} memory file(s))`)
}

async function syncToCC(directory: string): Promise<void> {
  const notes = await collectNotes(directory)
  if (!notes) return  // nothing meaningful to sync yet

  const ccMemoryDir = await resolveCCMemoryDir(directory)
  const out = join(ccMemoryDir, "from-opencode.md")
  await mkdir(dirname(out), { recursive: true })
  await writeFile(out, notes + "\n")
  console.error(`[memory-bridge-opencode] synced notes -> ${out}`)

  // Keep MEMORY.md index up-to-date so CC sees the actual facts
  await ensureCCMemoryIndex(ccMemoryDir, notes)
}

function buildSummary(personalContent: string): string {
  // Skip HTML comment blocks and headings; collect meaningful lines
  const lines = personalContent.split("\n").filter(line => {
    const l = line.trim()
    return l && !l.startsWith("<!--") && !l.startsWith("-->") && !l.startsWith("#")
  })
  if (!lines.length) return "OpenCode personal notes (empty)"
  const joined = lines.map(l => l.replace(/^[-*]\s+/, "")).join("; ")
  return joined.length > 120 ? joined.slice(0, 117) + "..." : joined
}

async function ensureCCMemoryIndex(ccMemoryDir: string, notes: string): Promise<void> {
  const memoryIndexPath = join(ccMemoryDir, "MEMORY.md")
  let content = ""
  try { content = await readFile(memoryIndexPath, "utf8") } catch { return }

  const summary = buildSummary(notes)
  const entry = `- [OpenCode personal notes](from-opencode.md) — ${summary}`

  if (content.includes("from-opencode.md")) {
    // Update existing entry with latest summary
    const updated = content.replace(/^.*from-opencode\.md.*$/m, entry)
    if (updated !== content) {
      await writeFile(memoryIndexPath, updated)
      console.error(`[memory-bridge-opencode] MEMORY.md: updated summary -> ${summary}`)
    }
  } else {
    await writeFile(memoryIndexPath, content.trimEnd() + "\n" + entry + "\n")
    console.error(`[memory-bridge-opencode] MEMORY.md: added entry -> ${summary}`)
  }
}

export const MemoryBridgeOpenCode: Plugin = async ({ directory }) => {
  // Run setup every session start (idempotent)
  await ensureSetup(directory)
  await ensurePersonalMd(directory)

  // Startup convergence: ① from-claude.md 가 없으면 CC 메모리에서 직접 부트스트랩
  // ② stray(beast) 메모 회수 ③ 밀린 동기화. 매 턴 종료 동기화와 합쳐져, 설치
  // 직후든 .opencode/ 를 지운 직후든 어떤 종료 방식이든 다리가 스스로 수렴한다.
  await bootstrapFromClaude(directory)
  await relocateBeastNotes(directory)
  await syncToCC(directory)

  return {
    event: async ({ event }) => {
      // session.idle fires at turn end (deprecated but still fires).
      // Fallback: session.status with status.type === "idle"
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const props = (event as any).properties
      const isIdle =
        event.type === "session.idle" ||
        (event.type === "session.status" && props?.status?.type === "idle")
      if (!isIdle) return
      await relocateBeastNotes(directory)
      await syncToCC(directory)
    },
  }
}
