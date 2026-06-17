#!/usr/bin/env node
"use strict";

const { spawn } = require("node:child_process");
const path = require("node:path");

const defaultCodexModel = "local/Qwen3.6-27B-Q4_0";
const defaultCodexModelProvider = "llama_cpp";
const defaultCodexBaseUrl = "http://127.0.0.1:8001/v1";

const serverInfo = {
  name: "ofxggml-codex-thread-spawner",
  version: "0.1.0",
};

let buffer = Buffer.alloc(0);
let nextCodexId = 1;

function send(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`);
  process.stdout.write(body);
}

function errorResponse(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

function textContent(text) {
  return { content: [{ type: "text", text }] };
}

function parseMessages() {
  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
      return;
    }
    const header = buffer.slice(0, headerEnd).toString("utf8");
    const match = /content-length:\s*(\d+)/i.exec(header);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }
    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) {
      return;
    }
    const body = buffer.slice(bodyStart, bodyEnd).toString("utf8");
    buffer = buffer.slice(bodyEnd);
    const message = JSON.parse(body);
    handleMessage(message).catch((error) => {
      errorResponse(typeof message.id !== "undefined" ? message.id : null, -32603, error.message || String(error));
    });
  }
}

function toolList() {
  const spawnCodexThreadTool = {
    name: "spawn_codex_thread",
    description:
      "Start a separate Codex app-server thread and submit one prompt to it. Use for explicit sidecar or subagent work.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      properties: {
        prompt: {
          type: "string",
          description: "Initial prompt to send to the spawned Codex thread.",
        },
        cwd: {
          type: "string",
          description: "Optional working directory for the spawned turn.",
        },
        model: {
          type: "string",
          description: "Optional Codex model override.",
        },
        model_provider: {
          type: "string",
          description: "Optional Codex model provider override.",
        },
        dry_run: {
          type: "boolean",
          description: "Return the planned app-server calls without launching Codex.",
        },
      },
      required: ["prompt"],
    },
  };
  spawnCodexThreadTool.type = "function";
  spawnCodexThreadTool.function = {
    name: spawnCodexThreadTool.name,
    description: spawnCodexThreadTool.description,
    parameters: spawnCodexThreadTool.inputSchema,
  };
  return {
    tools: [spawnCodexThreadTool],
  };
}

function splitPathList(value) {
  if (typeof value !== "string" || !value.trim()) {
    return [];
  }
  return value.split(path.delimiter).map((entry) => entry.trim()).filter(Boolean);
}

function normalizePath(value) {
  return path.resolve(value).toLowerCase();
}

function isPathInside(candidate, root) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function allowedCwdRoots() {
  const roots = [process.cwd()];
  roots.push(...splitPathList(process.env.OFXGGML_CODEX_THREAD_ALLOWED_ROOTS));
  if (process.env.OFXGGML_CODEX_ADDON_ROOT) {
    roots.push(process.env.OFXGGML_CODEX_ADDON_ROOT);
  }
  const normalized = [];
  const seen = new Set();
  for (const root of roots) {
    const resolved = path.resolve(root);
    const key = normalizePath(resolved);
    if (!seen.has(key)) {
      seen.add(key);
      normalized.push(resolved);
    }
  }
  return normalized;
}

function resolveSpawnCwd(value) {
  const requested = typeof value === "string" && value.trim()
    ? path.resolve(value.trim())
    : process.cwd();
  const candidate = normalizePath(requested);
  const roots = allowedCwdRoots();
  const allowed = roots.some((root) => isPathInside(candidate, normalizePath(root)));
  if (!allowed) {
    throw new Error(`cwd is outside the allowed Codex thread roots: ${requested}`);
  }
  return { cwd: requested, allowedRoots: roots };
}

function resolveProvider(value) {
  const provider = typeof value === "string" && value.trim()
    ? value.trim()
    : (process.env.OFXGGML_CODEX_MODEL_PROVIDER || defaultCodexModelProvider);
  if (provider !== defaultCodexModelProvider) {
    throw new Error(`spawn_codex_thread only supports ${defaultCodexModelProvider}; received ${provider}`);
  }
  return provider;
}

function callCodexThreadSpawner(args) {
  const prompt = typeof args.prompt === "string" ? args.prompt.trim() : "";
  if (!prompt) {
    throw new Error("prompt is required");
  }

  const cwdInfo = resolveSpawnCwd(args.cwd);
  const cwd = cwdInfo.cwd;
  const model = typeof args.model === "string" && args.model.trim()
    ? args.model.trim()
    : (process.env.OFXGGML_CODEX_MODEL || defaultCodexModel);
  const modelProvider = resolveProvider(args.model_provider);
  const baseUrl = process.env.OFXGGML_CODEX_BASE_URL || defaultCodexBaseUrl;
  const dryRun = Boolean(args.dry_run);
  const plan = {
    transport: "codex app-server stdio",
    local_provider: {
      model,
      modelProvider,
      baseUrl,
      allowedCwdRoots: cwdInfo.allowedRoots,
    },
    thread_start: {
      cwd,
      ...(model ? { model } : {}),
      modelProvider,
      approvalPolicy: "never",
      sandbox: "workspace-write",
      ephemeral: true,
      personality: "none",
      threadSource: "subagent",
    },
    turn_start: {
      cwd,
      input: [{ type: "text", text: prompt }],
    },
  };

  if (dryRun) {
    return Promise.resolve(textContent(JSON.stringify(plan, null, 2)));
  }

  return spawnCodexThread(plan);
}
function sendCodex(proc, method, params) {
  const id = nextCodexId++;
  proc.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method, id, params })}\n`);
  return id;
}

function spawnCodexThread(plan) {
  return new Promise((resolve, reject) => {
    const codexExe = process.env.OFXGGML_CODEX_EXE || process.env.CODEX_CLI_PATH || "codex";
    let proc;
    try {
      proc = spawn(codexExe, ["app-server", "--listen", "stdio://"], {
        cwd: plan.turn_start.cwd,
        stdio: ["pipe", "pipe", "pipe"],
        windowsHide: true,
      });
    } catch (error) {
      reject(new Error(`failed to start codex app-server (${codexExe}): ${error.message || String(error)}`));
      return;
    }
    const initializeId = sendCodex(proc, "initialize", {
      clientInfo: {
        name: "ofxggml_codex_thread_mcp",
        title: "ofxGgml Codex Thread MCP",
        version: serverInfo.version,
      },
      capabilities: { experimentalApi: true },
    });
    proc.stdin.write(`${JSON.stringify({ jsonrpc: "2.0", method: "initialized", params: {} })}\n`);

    let threadStartId = 0;
    let turnStartId = 0;
    let settled = false;
    let stdout = "";
    let stderr = "";
    let threadId = "";
    let turnStarted = false;
    const appServerMessages = [];
    const timeoutMs = Number(process.env.OFXGGML_CODEX_THREAD_SPAWN_TIMEOUT_MS || 90000);

    function remember(message) {
      appServerMessages.push(message);
      if (appServerMessages.length > 12) {
        appServerMessages.shift();
      }
    }

    function stopAppServer() {
      if (!proc || proc.killed) {
        return;
      }
      if (process.platform === "win32" && proc.pid) {
        spawn("taskkill", ["/pid", String(proc.pid), "/t", "/f"], {
          stdio: "ignore",
          windowsHide: true,
        }).on("error", () => {});
      } else {
        proc.kill();
      }
    }

    function settle(error, result) {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      stopAppServer();
      if (error) {
        reject(error);
      } else {
        resolve(result);
      }
    }

    function appServerError(message) {
      const details = [
        message,
        stderr.trim() ? `stderr: ${stderr.trim()}` : "",
        appServerMessages.length
          ? `recent app-server messages: ${JSON.stringify(appServerMessages)}`
          : "",
      ].filter(Boolean).join("\n");
      return new Error(details);
    }

    const timer = setTimeout(() => {
      settle(appServerError(`codex app-server timed out after ${timeoutMs}ms`));
    }, Math.max(1000, timeoutMs));

    function startTurn(id) {
      if (!id || turnStarted) {
        return;
      }
      threadId = id;
      turnStarted = true;
      turnStartId = sendCodex(proc, "turn/start", {
        threadId,
        cwd: plan.turn_start.cwd,
        input: plan.turn_start.input,
        approvalPolicy: "never",
        sandboxPolicy: {
          type: "workspaceWrite",
          writableRoots: [plan.turn_start.cwd],
          networkAccess: false,
        },
        effort: "none",
        summary: "none",
        personality: "none",
      });
    }

    function readThreadId(result) {
      if (!result) {
        return "";
      }
      return result.threadId || result.id || (result.thread && result.thread.id) || "";
    }

    proc.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });
    proc.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
      for (;;) {
        const newline = stdout.indexOf("\n");
        if (newline < 0) {
          break;
        }
        const line = stdout.slice(0, newline).trim();
        stdout = stdout.slice(newline + 1);
        if (!line) {
          continue;
        }
        let message;
        try {
          message = JSON.parse(line);
        } catch {
          continue;
        }
        remember(message);
        if (message.error) {
          settle(appServerError(`codex app-server ${message.id ? `request ${message.id}` : "notification"} failed: ${JSON.stringify(message.error)}`));
          return;
        }
        if (message.id === initializeId && message.result) {
          threadStartId = sendCodex(proc, "thread/start", plan.thread_start);
          continue;
        }
        if (message.id === threadStartId && message.result) {
          startTurn(readThreadId(message.result));
          continue;
        }
        if (message.method === "thread/started") {
          startTurn(readThreadId(message.params));
          continue;
        }
        if (message.id === turnStartId && message.result) {
          continue;
        }
        if (message.method === "turn/completed") {
          const turn = message.params && message.params.turn;
          const status = turn && turn.status ? turn.status : "completed";
          settle(null, textContent(JSON.stringify({
            status: "spawned",
            thread_id: threadId,
            turn_status: status,
            completed: status === "completed",
          }, null, 2)));
          return;
        }
      }
    });
    proc.on("error", (error) => {
      settle(new Error(`failed to start codex app-server (${codexExe}): ${error.message || String(error)}`));
    });
    proc.on("exit", (code) => {
      if (!settled) {
        settle(appServerError(`codex app-server exited before completion (${code})`));
      }
    });
  });
}

async function handleMessage(message) {
  const { id, method, params } = message;
  if (method === "initialize") {
    send({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion: params && params.protocolVersion ? params.protocolVersion : "2024-11-05",
        capabilities: { tools: {} },
        serverInfo,
        instructions:
          "Use spawn_codex_thread only when the user explicitly asks for a separate Codex thread or sidecar agent.",
      },
    });
    return;
  }
  if (method === "tools/list") {
    send({ jsonrpc: "2.0", id, result: toolList() });
    return;
  }
  if (method === "tools/call") {
    const name = params && params.name;
    if (name !== "spawn_codex_thread") {
      errorResponse(id, -32602, `unknown tool: ${name}`);
      return;
    }
    const result = await callCodexThreadSpawner(params.arguments || {});
    send({ jsonrpc: "2.0", id, result });
    return;
  }
  if (typeof id !== "undefined") {
    errorResponse(id, -32601, `unknown method: ${method}`);
  }
}

process.stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  parseMessages();
});
