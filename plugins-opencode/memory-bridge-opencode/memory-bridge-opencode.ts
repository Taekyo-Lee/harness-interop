import type { Plugin } from "@opencode-ai/plugin"
import { homedir } from "node:os"
import { join, dirname } from "node:path"
import { mkdir, copyFile, access, readFile, writeFile } from "node:fs/promises"

// Paths relative to project directory
const PERSONAL_NOTES = ".opencode/personal.md"
const FROM_CLAUDE = ".opencode/from-claude.md"
const CC_MEMORY_POINTER = ".opencode/.cc-memory-path"
const PLUGIN_FILE = ".opencode/plugin/memory-bridge-opencode.ts"

// Header injected into personal.md so OpenCode knows where to write memories
const PERSONAL_HEADER =
  "<!-- memory-bridge-opencode: this file is your project-scoped personal memory.\n" +
  "     When asked to remember something for this project, append it here.\n" +
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

// Feature 3: sync personal.md → CC memory/from-opencode.md
async function syncToCC(directory: string): Promise<void> {
  const src = join(directory, ".opencode", "personal.md")
  try { await access(src) } catch { return }  // personal.md doesn't exist yet

  // Plan B: read exact CC memory path from pointer file written by memory-bridge.sh
  let ccMemoryDir = ""
  try {
    const ptr = (await readFile(join(directory, CC_MEMORY_POINTER), "utf8")).trim()
    if (ptr) { ccMemoryDir = ptr; console.error(`[memory-bridge-opencode] cc_home from pointer: ${ptr}`) }
  } catch { /* pointer not written yet — CC session hasn't ended */ }

  if (!ccMemoryDir) {
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
      try { await access(candidate); ccMemoryDir = candidate; break } catch { /* try next */ }
    }
    if (!ccMemoryDir) ccMemoryDir = candidates[0]  // none exist yet -> production default
    console.error(`[memory-bridge-opencode] cc_home from fallback-probe: ${ccMemoryDir}`)
  }

  const out = join(ccMemoryDir, "from-opencode.md")
  await mkdir(dirname(out), { recursive: true })
  await copyFile(src, out)
  console.error(`[memory-bridge-opencode] synced ${src} -> ${out}`)

  // Keep MEMORY.md index up-to-date so CC sees the actual facts from personal.md
  await ensureCCMemoryIndex(ccMemoryDir, src)
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

async function ensureCCMemoryIndex(ccMemoryDir: string, src: string): Promise<void> {
  const memoryIndexPath = join(ccMemoryDir, "MEMORY.md")
  let content = ""
  try { content = await readFile(memoryIndexPath, "utf8") } catch { return }

  const personalContent = await readFile(src, "utf8")
  const summary = buildSummary(personalContent)
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

  // Startup catch-up: sync whatever a killed previous session left behind.
  // Combined with the per-turn sync below, exit mode (/exit, /quit, Ctrl-C,
  // kill) never matters — the bridge converges on load and on every turn end.
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
      await syncToCC(directory)
    },
  }
}
