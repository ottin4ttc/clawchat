/**
 * OpenClaw Bridge — connects a local OpenClaw gateway to ClawChat relay.
 *
 * This bridge acts as both:
 *   1. A ClawChat "gateway" that registers with the relay
 *   2. A "client" that talks to your local OpenClaw gateway via its WebSocket API
 *
 * Usage:
 *   bun scripts/openclaw-bridge.ts [options]
 *
 * Options:
 *   --openclaw <url>   OpenClaw gateway WebSocket (default: ws://localhost:18789)
 *   --relay <url>      ClawChat relay WebSocket (default: wss://clawchat-production-db31.up.railway.app)
 *   --token <token>    OpenClaw gateway auth token (REQUIRED — must match gateway.auth.token)
 *   --session <key>    OpenClaw session key (default: clawchat)
 */

import { parseArgs } from "node:util";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

const { values: args } = parseArgs({
  options: {
    openclaw: { type: "string", default: "ws://localhost:18789" },
    relay: { type: "string", default: "wss://clawchat-production-db31.up.railway.app" },
    token: { type: "string", default: "" },
    session: { type: "string", default: "clawchat" },
    config: { type: "string", default: "" },
  },
});

const OPENCLAW_URL = args.openclaw!;
const RELAY_URL = args.relay!;
const AUTH_TOKEN = args.token!;
const SESSION_KEY = args.session!;
const GATEWAY_ID = "openclaw-bridge";
const GATEWAY_TOKEN = "bridge-openclaw-stable-token";

// ---------------------------------------------------------------------------
// Load agent info from OpenClaw config
// ---------------------------------------------------------------------------

interface AgentMeta {
  id: string;
  name: string;
  model: string;
  availableModels: string[];
  avatar: string;
}

function makeAgentId(name: string): string {
  const trimmed = name.trim();
  if (!trimmed) return "agent";

  const normalized = trimmed
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, "-")
    .replace(/^-+|-+$/g, "");

  return normalized || trimmed;
}

function encodeAgentDescriptor(meta: AgentMeta): string {
  return `${meta.id}::${meta.name}::${meta.model}::${meta.availableModels.join("|")}`;
}

function loadAgentMeta(): AgentMeta {
  const configPath = args.config || path.join(
    process.env.HOME || "/root",
    ".openclaw/openclaw.json"
  );

  const meta: AgentMeta = {
    id: "default",
    name: "Agent",
    model: "unknown",
    availableModels: [],
    avatar: "",
  };

  try {
    const raw = fs.readFileSync(configPath, "utf-8");
    const config = JSON.parse(raw);

    const primary = config?.agents?.defaults?.model?.primary;
    if (primary) {
      meta.model = primary.includes("/")
        ? primary.split("/").pop()!
        : primary;
    }

    const fallbacks = (config?.agents?.defaults?.model?.fallbacks ?? [])
      .map((value: unknown) => {
        if (typeof value !== "string" || !value) return null;
        return value.includes("/") ? value.split("/").pop()! : value;
      })
      .filter((value: string | null): value is string => value !== null);
    meta.availableModels = Array.from(new Set([meta.model, ...fallbacks].filter(Boolean)));

    const wsDir = config?.agents?.defaults?.workspace
      || path.join(process.env.HOME || "/root", ".openclaw/workspace");

    for (const file of ["IDENTITY.md", "SOUL.md"]) {
      try {
        const content = fs.readFileSync(path.join(wsDir, file), "utf-8");
        const namePatterns = [
          /\*\*名字[：:]\*\*\s*(.+)/,
          /你叫(.{1,10})[。，\.]/,
          /名字[：:]\s*(.+)/,
          /# (.+) - /,
        ];
        for (const pat of namePatterns) {
          const m = content.match(pat);
          if (m) {
            meta.name = m[1].trim();
            break;
          }
        }
        if (meta.name !== "Agent") break;
      } catch {}
    }
    meta.id = makeAgentId(meta.name);
  } catch (e) {
    console.warn(`[config] Could not read OpenClaw config: ${e}`);
  }

  return meta;
}

const AGENT_META = loadAgentMeta();
const RELAY_AGENT = encodeAgentDescriptor(AGENT_META);
console.log(`[config] Agent: "${AGENT_META.name}" model=${AGENT_META.model}`);

// ---------------------------------------------------------------------------
// Device Identity (Ed25519 keypair for OpenClaw gateway auth)
// ---------------------------------------------------------------------------

const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

function base64UrlEncode(buf: Buffer): string {
  return buf.toString("base64").replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/g, "");
}

const { publicKey: PUB_KEY, privateKey: PRIV_KEY } = crypto.generateKeyPairSync("ed25519");
const PUB_KEY_PEM = PUB_KEY.export({ type: "spki", format: "pem" }).toString();
const PRIV_KEY_PEM = PRIV_KEY.export({ type: "pkcs8", format: "pem" }).toString();
const PUB_KEY_RAW = (() => {
  const spki = PUB_KEY.export({ type: "spki", format: "der" }) as Buffer;
  return spki.subarray(ED25519_SPKI_PREFIX.length);
})();
const DEVICE_ID = crypto.createHash("sha256").update(PUB_KEY_RAW).digest("hex");
const PUB_KEY_B64URL = base64UrlEncode(PUB_KEY_RAW);

function signPayload(payload: string): string {
  const sig = crypto.sign(null, Buffer.from(payload, "utf8"), PRIV_KEY);
  return base64UrlEncode(sig);
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

let openclawWs: WebSocket | null = null;
let relayWs: WebSocket | null = null;
let openclawReady = false;
let relayReady = false;

// Track active runs: runId → { relayMessageId }
const activeRuns = new Map<string, { relayMessageId: string }>();

// ---------------------------------------------------------------------------
// OpenClaw Gateway Connection
// ---------------------------------------------------------------------------

function connectOpenClaw() {
  console.log(`[openclaw] Connecting to ${OPENCLAW_URL} ...`);
  openclawWs = new WebSocket(OPENCLAW_URL);

  openclawWs.addEventListener("open", () => {
    console.log("[openclaw] WebSocket open, waiting for challenge...");
  });

  openclawWs.addEventListener("message", (event) => {
    const frame = JSON.parse(event.data as string);
    handleOpenClawFrame(frame);
  });

  openclawWs.addEventListener("close", (event) => {
    console.log(`[openclaw] Disconnected (code=${event.code})`);
    openclawReady = false;
    // Reconnect after 5s
    setTimeout(connectOpenClaw, 5000);
  });

  openclawWs.addEventListener("error", () => {
    console.error("[openclaw] Connection error");
  });
}

function handleOpenClawFrame(frame: any) {
  switch (frame.type) {
    case "event":
      handleOpenClawEvent(frame);
      break;

    case "res":
      // Response to our requests (connect, chat.send, etc.)
      if (frame.ok === false) {
        console.error(`[openclaw] Request failed:`, frame.error);
      } else if (frame.payload?.type === "hello-ok") {
        console.log(`[openclaw] Connected! Server: ${frame.payload.server?.version ?? "unknown"}`);
        openclawReady = true;
      }
      break;
  }
}

function handleOpenClawEvent(frame: any) {
  const { event, payload } = frame;

  switch (event) {
    case "connect.challenge": {
      // Build device auth signature (v3 payload format)
      const role = "operator";
      const scopes = ["operator.admin"];
      const signedAtMs = Date.now();
      const nonce = payload?.nonce ?? crypto.randomUUID();
      const platform = "clawchat-bridge";
      const clientId = "gateway-client";
      const clientMode = "backend";

      const authPayload = [
        "v3", DEVICE_ID, clientId, clientMode, role,
        scopes.join(","), String(signedAtMs), AUTH_TOKEN || "",
        nonce, platform, "", // deviceFamily
      ].join("|");
      const signature = signPayload(authPayload);

      const connectParams: any = {
        minProtocol: 3,
        maxProtocol: 3,
        role,
        client: {
          id: clientId,
          mode: clientMode,
          version: "0.1.0",
          platform,
        },
        device: {
          id: DEVICE_ID,
          publicKey: PUB_KEY_B64URL,
          signature,
          signedAt: signedAtMs,
          nonce,
        },
        scopes,
        caps: ["tool-events"],
      };
      if (AUTH_TOKEN) {
        connectParams.auth = { token: AUTH_TOKEN };
      }
      sendToOpenClaw({
        type: "req",
        id: crypto.randomUUID(),
        method: "connect",
        params: connectParams,
      });
      break;
    }

    case "chat": {
      handleChatEvent(payload);
      break;
    }
  }
}

function handleChatEvent(payload: any) {
  const { runId, state, message, stopReason } = payload;
  const run = activeRuns.get(runId);
  if (!run) return; // Not our run

  if (state === "delta" && message?.content) {
    // Extract text from content blocks
    for (const block of message.content) {
      if (block.type === "text" && block.text) {
        // Send as streaming delta to relay
        sendToRelay({
          type: "message.stream",
          id: run.relayMessageId,
          ts: Date.now(),
          agentId: AGENT_META.id,
          delta: block.text,
          phase: "streaming",
        });
      } else if (block.type === "thinking" && block.thinking) {
        // Send as reasoning block
        sendToRelay({
          type: "message.reasoning",
          id: run.relayMessageId,
          ts: Date.now(),
          agentId: AGENT_META.id,
          text: block.thinking,
          phase: "streaming",
        });
      } else if (block.type === "tool_use") {
        sendToRelay({
          type: "tool.event",
          id: crypto.randomUUID(),
          ts: Date.now(),
          agentId: AGENT_META.id,
          tool: block.name || "tool",
          phase: "start",
          label: block.name || "Tool call",
          input: block.input || {},
        });
      } else if (block.type === "tool_result") {
        sendToRelay({
          type: "tool.event",
          id: crypto.randomUUID(),
          ts: Date.now(),
          agentId: AGENT_META.id,
          tool: "tool",
          phase: "result",
          label: "Done",
          result: block.content,
        });
      }
    }
  }

  if (state === "final") {
    // Send stream done
    let finalText = "";
    if (message?.content) {
      finalText = message.content
        .filter((b: any) => b.type === "text")
        .map((b: any) => b.text)
        .join("");
    }

    sendToRelay({
      type: "message.stream",
      id: run.relayMessageId,
      ts: Date.now(),
      agentId: AGENT_META.id,
      delta: "",
      phase: "done",
      finalText,
    });

    activeRuns.delete(runId);
    console.log(`[openclaw] Run ${runId.slice(0, 8)}... completed (${stopReason})`);
  }

  if (state === "error") {
    sendToRelay({
      type: "message.stream",
      id: run.relayMessageId,
      ts: Date.now(),
      delta: "",
      phase: "error",
    });
    activeRuns.delete(runId);
    console.error(`[openclaw] Run ${runId.slice(0, 8)}... errored`);
  }

  if (state === "aborted") {
    sendToRelay({
      type: "message.stream",
      id: run.relayMessageId,
      ts: Date.now(),
      delta: "",
      phase: "done",
      finalText: "[aborted]",
    });
    activeRuns.delete(runId);
  }
}

// ---------------------------------------------------------------------------
// ClawChat Relay Connection
// ---------------------------------------------------------------------------

function connectRelay() {
  console.log(`[relay] Connecting to ${RELAY_URL}/ws/gateway ...`);
  relayWs = new WebSocket(`${RELAY_URL}/ws/gateway`);

  relayWs.addEventListener("open", () => {
    console.log("[relay] WebSocket open, registering...");
    sendToRelay({
      type: "gateway.register",
      id: crypto.randomUUID(),
      ts: Date.now(),
      token: GATEWAY_TOKEN,
      gatewayId: GATEWAY_ID,
      protocolVersion: "0.1.0",
      version: "0.1.0",
      agents: [RELAY_AGENT],
      agentsMeta: {
        [RELAY_AGENT]: {
          name: AGENT_META.name,
          model: AGENT_META.model,
          avatar: AGENT_META.avatar,
        },
      },
    });
  });

  relayWs.addEventListener("message", (event) => {
    const msg = JSON.parse(event.data as string);
    handleRelayMessage(msg);
  });

  relayWs.addEventListener("close", (event) => {
    console.log(`[relay] Disconnected (code=${event.code})`);
    relayReady = false;
    setTimeout(connectRelay, 5000);
  });

  relayWs.addEventListener("error", () => {
    console.error("[relay] Connection error");
  });
}

function handleRelayMessage(msg: any) {
  switch (msg.type) {
    case "gateway.registered":
      console.log(`[relay] Registered! Paired devices: ${msg.pairedDevices}`);
      relayReady = true;

      broadcastStatus();

      sendToRelay({
        type: "pair.generate",
        id: crypto.randomUUID(),
        ts: Date.now(),
      });
      break;

    case "pair.code":
      console.log("");
      console.log("========================================");
      console.log(`  Pairing Code:  ${msg.code}`);
      console.log(`  Expires: ${new Date(msg.expiresAt).toLocaleTimeString()}`);
      console.log("========================================");
      console.log("");
      console.log("Connect with CLI:");
      console.log(`  bun cli/src/index.ts --relay ${RELAY_URL} --code ${msg.code}`);
      console.log("");
      break;

    case "app.paired":
    case "app.connected":
      console.log(`[relay] Device ${msg.type}, broadcasting status...`);
      broadcastStatus();
      break;

    case "status.request":
      console.log("[relay] Received status.request, responding...");
      sendToRelay({
        type: "status.response",
        id: msg.id || crypto.randomUUID(),
        ts: Date.now(),
        gatewayOnline: openclawReady,
        agents: [RELAY_AGENT],
        agentsMeta: {
          [RELAY_AGENT]: {
            name: AGENT_META.name,
            model: AGENT_META.model,
            avatar: AGENT_META.avatar,
          },
        },
        connectedDevices: 1,
      });
      break;

    case "message.inbound":
      handleInboundMessage(msg);
      break;

    case "typing":
      break;

    default:
      break;
  }
}

function handleInboundMessage(msg: any) {
  if (!openclawReady) {
    sendToRelay({
      type: "error",
      id: crypto.randomUUID(),
      ts: Date.now(),
      code: "gateway_offline",
      message: "OpenClaw gateway is not connected",
      requestId: msg.id,
    });
    return;
  }

  const attachments = Array.isArray(msg.attachments) ? msg.attachments : undefined;
  console.log(`[user] ${msg.text || "[attachment]"}${attachments?.length ? ` (+${attachments.length} attachment${attachments.length > 1 ? "s" : ""})` : ""}`);

  // Send typing indicator
  sendToRelay({
    type: "typing",
    id: crypto.randomUUID(),
    ts: Date.now(),
    agentId: AGENT_META.id,
    active: true,
  });

  // Create a run
  const idempotencyKey = crypto.randomUUID();
  const relayMessageId = crypto.randomUUID();

  // Track the run
  activeRuns.set(idempotencyKey, { relayMessageId });

  // Send to OpenClaw
  sendToOpenClaw({
    type: "req",
    id: crypto.randomUUID(),
    method: "chat.send",
    params: {
      sessionKey: SESSION_KEY,
      message: msg.text || "",
      attachments,
      idempotencyKey,
    },
  });
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function broadcastStatus() {
  sendToRelay({
    type: "status.response",
    id: crypto.randomUUID(),
    ts: Date.now(),
    gatewayOnline: openclawReady,
    agents: [RELAY_AGENT],
    agentsMeta: {
      [RELAY_AGENT]: {
        name: AGENT_META.name,
        model: AGENT_META.model,
        avatar: AGENT_META.avatar,
      },
    },
    connectedDevices: 1,
  });
}

function sendToOpenClaw(msg: any) {
  if (openclawWs?.readyState === WebSocket.OPEN) {
    openclawWs.send(JSON.stringify(msg));
  }
}

function sendToRelay(msg: any) {
  if (relayWs?.readyState === WebSocket.OPEN) {
    relayWs.send(JSON.stringify(msg));
  }
}

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

console.log("ClawChat ↔ OpenClaw Bridge");
console.log(`  OpenClaw: ${OPENCLAW_URL}`);
console.log(`  Relay:    ${RELAY_URL}`);
console.log(`  Session:  ${SESSION_KEY}`);
console.log(`  Auth:     ${AUTH_TOKEN ? "token provided" : "⚠ no token (will fail device identity check)"}`);
console.log("");

if (!AUTH_TOKEN) {
  console.warn("WARNING: --token is required to connect to the OpenClaw gateway.");
  console.warn("  1. Set a gateway token:  openclaw config set gateway.auth.token YOUR_SECRET");
  console.warn("  2. Pass it to bridge:    bun scripts/openclaw-bridge.ts --token YOUR_SECRET");
  console.warn("");
}

connectOpenClaw();
connectRelay();

process.on("SIGINT", () => {
  console.log("\nShutting down...");
  openclawWs?.close();
  relayWs?.close();
  process.exit(0);
});
