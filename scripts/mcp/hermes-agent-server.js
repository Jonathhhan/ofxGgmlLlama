#!/usr/bin/env node
"use strict";

const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");

const defaultHermesModel = "local/Qwen3.6-27B-Q4_0";
const defaultHermesProvider = "custom";
const defaultHermesExe = "hermes";
const defaultHermesBaseUrl = "http://127.0.0.1:8001/v1";
const defaultHermesEndpointAllowlist = "http://127.0.0.1:8001/v1,http://localhost:8001/v1";
const defaultHermesSafeToolsets = "web,skills,session_search,clarify,todo";
const defaultOutputLimitBytes = 512 * 1024;
const defaultTimeoutMs = 300000;
const defaultMaxTimeoutMs = 300000;
const maxHeaderBytes = 16 * 1024;
const maxBodyBytes = 1024 * 1024;

const serverInfo = {
  name: "ofxggml-hermes-agent",
  version: "0.1.0",
};

let buffer = Buffer.alloc(0);

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
    if (buffer.length > maxHeaderBytes && buffer.indexOf("\r\n\r\n") < 0) {
      buffer = Buffer.alloc(0);
      errorResponse(null, -32600, `MCP header exceeded ${maxHeaderBytes} bytes`);
      return;
    }
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0) {
      return;
    }
    if (headerEnd > maxHeaderBytes) {
      buffer = buffer.slice(headerEnd + 4);
      errorResponse(null, -32600, `MCP header exceeded ${maxHeaderBytes} bytes`);
      continue;
    }
    const header = buffer.slice(0, headerEnd).toString("utf8");
    const match = /content-length:\s*(\d+)/i.exec(header);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }
    const length = Number(match[1]);
    if (!Number.isFinite(length) || length < 0 || length > maxBodyBytes) {
      buffer = buffer.slice(headerEnd + 4);
      errorResponse(null, -32600, `MCP body exceeded ${maxBodyBytes} bytes`);
      continue;
    }
    const bodyStart = headerEnd + 4;
    const bodyEnd = bodyStart + length;
    if (buffer.length < bodyEnd) {
      return;
    }
    const body = buffer.slice(bodyStart, bodyEnd).toString("utf8");
    buffer = buffer.slice(bodyEnd);
    let message;
    try {
      message = JSON.parse(body);
    } catch (error) {
      errorResponse(null, -32700, `invalid JSON-RPC message: ${error.message || String(error)}`);
      continue;
    }
    handleMessage(message).catch((error) => {
      errorResponse(typeof message.id !== "undefined" ? message.id : null, -32603, error.message || String(error));
    });
  }
}

function toolList() {
  const runHermesAgentTool = {
    name: "run_hermes_agent",
    description:
      "Run Hermes Agent once with a prompt and return its final response. Use only when the user explicitly asks for Hermes as a sidecar agent.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      properties: {
        prompt: {
          type: "string",
          description: "Prompt to send to Hermes one-shot mode.",
        },
        cwd: {
          type: "string",
          description: "Optional working directory for the Hermes run.",
        },
        model: {
          type: "string",
          description: "Optional Hermes model override.",
        },
        provider: {
          type: "string",
          description: "Optional Hermes provider override.",
        },
        toolsets: {
          type: "string",
          description: "Optional comma-separated Hermes toolsets to enable. Each entry must be allowed by OFXGGML_HERMES_SAFE_TOOLSETS.",
        },
        allow_hooks: {
          type: "boolean",
          description: "Request --accept-hooks for Hermes. Honored only when OFXGGML_HERMES_ALLOW_HOOKS is true.",
        },
        safe_mode: {
          type: "boolean",
          description: "Pass --safe-mode to Hermes. Defaults to false unless OFXGGML_HERMES_SAFE_MODE is true.",
        },
        timeout_ms: {
          type: "integer",
          description: "Optional timeout in milliseconds.",
        },
        dry_run: {
          type: "boolean",
          description: "Return the planned Hermes command without launching Hermes.",
        },
      },
      required: ["prompt"],
    },
  };
  const preflightHermesAgentTool = {
    name: "preflight_hermes_agent",
    description:
      "Check the local Hermes Agent sidecar command, cwd roots, model/provider, toolset allowlist, and optionally the OpenAI-compatible endpoint.",
    inputSchema: {
      type: "object",
      additionalProperties: false,
      properties: {
        cwd: {
          type: "string",
          description: "Optional working directory to validate against the Hermes allowed roots.",
        },
        model: {
          type: "string",
          description: "Optional Hermes model override.",
        },
        provider: {
          type: "string",
          description: "Optional Hermes provider override.",
        },
        endpoint: {
          type: "string",
          description: "Optional OpenAI-compatible endpoint root, such as http://127.0.0.1:8001/v1.",
        },
        check_endpoint: {
          type: "boolean",
          description: "When true, request /models from the endpoint.",
        },
        timeout_ms: {
          type: "integer",
          description: "Optional timeout in milliseconds for command and endpoint checks.",
        },
      },
    },
  };
  runHermesAgentTool.type = "function";
  runHermesAgentTool.function = {
    name: runHermesAgentTool.name,
    description: runHermesAgentTool.description,
    parameters: runHermesAgentTool.inputSchema,
  };
  preflightHermesAgentTool.type = "function";
  preflightHermesAgentTool.function = {
    name: preflightHermesAgentTool.name,
    description: preflightHermesAgentTool.description,
    parameters: preflightHermesAgentTool.inputSchema,
  };
  return { tools: [runHermesAgentTool, preflightHermesAgentTool] };
}

function splitPathList(value) {
  if (typeof value !== "string" || !value.trim()) {
    return [];
  }
  return value.split(path.delimiter).map((entry) => entry.trim()).filter(Boolean);
}

function splitCommaList(value) {
  if (typeof value !== "string" || !value.trim()) {
    return [];
  }
  return value.split(",").map((entry) => entry.trim()).filter(Boolean);
}

function booleanValue(value, fallback = false) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value !== "string") {
    return fallback;
  }
  const normalized = value.trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

function normalizePath(value) {
  return path.resolve(value).toLowerCase();
}

function realPath(value) {
  return fs.realpathSync.native(path.resolve(value));
}

function isPathInside(candidate, root) {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function allowedCwdRoots() {
  const roots = splitPathList(process.env.OFXGGML_HERMES_ALLOWED_ROOTS);
  if (process.env.OFXGGML_CODEX_ADDON_ROOT) {
    roots.push(process.env.OFXGGML_CODEX_ADDON_ROOT);
  }
  if (roots.length === 0) {
    throw new Error("OFXGGML_HERMES_ALLOWED_ROOTS or OFXGGML_CODEX_ADDON_ROOT must be set before running Hermes");
  }
  const normalized = [];
  const seen = new Set();
  for (const root of roots) {
    let resolved;
    try {
      resolved = realPath(root);
    } catch (error) {
      throw new Error(`Hermes allowed root does not exist: ${root}`);
    }
    const key = normalizePath(resolved);
    if (!seen.has(key)) {
      seen.add(key);
      normalized.push(resolved);
    }
  }
  return normalized;
}

function resolveRunCwd(value) {
  const requested = typeof value === "string" && value.trim()
    ? path.resolve(value.trim())
    : process.cwd();
  let resolvedCandidate;
  try {
    resolvedCandidate = realPath(requested);
  } catch (error) {
    throw new Error(`Hermes cwd does not exist: ${requested}`);
  }
  const candidate = normalizePath(resolvedCandidate);
  const roots = allowedCwdRoots();
  const allowed = roots.some((root) => isPathInside(candidate, normalizePath(root)));
  if (!allowed) {
    throw new Error(`cwd is outside the allowed Hermes roots: ${requested}`);
  }
  return { cwd: resolvedCandidate, allowedRoots: roots };
}

function resolveString(value, fallback) {
  return typeof value === "string" && value.trim() ? value.trim() : fallback;
}

function resolveTimeoutMs(value, fallback) {
  const parsed = Number(value || fallback);
  const maxTimeoutMs = resolveMaxTimeoutMs(process.env.OFXGGML_HERMES_MAX_TIMEOUT_MS);
  if (!Number.isFinite(parsed)) {
    return Math.min(maxTimeoutMs, Math.max(1000, fallback));
  }
  return Math.min(maxTimeoutMs, Math.max(1000, parsed));
}

function resolveMaxTimeoutMs(value) {
  const parsed = Number(value || defaultMaxTimeoutMs);
  if (!Number.isFinite(parsed)) {
    return defaultMaxTimeoutMs;
  }
  return Math.max(1000, parsed);
}

function resolveOutputLimitBytes(value) {
  const parsed = Number(value || defaultOutputLimitBytes);
  if (!Number.isFinite(parsed)) {
    return defaultOutputLimitBytes;
  }
  return Math.max(4096, parsed);
}

function safeToolsetAllowlist() {
  const configured = splitCommaList(process.env.OFXGGML_HERMES_SAFE_TOOLSETS);
  return new Set(configured.length > 0 ? configured : splitCommaList(defaultHermesSafeToolsets));
}

function resolveToolsets(value) {
  const requested = resolveString(value, process.env.OFXGGML_HERMES_TOOLSETS || defaultHermesSafeToolsets);
  const toolsets = splitCommaList(requested);
  const allowed = safeToolsetAllowlist();
  const denied = toolsets.filter((toolset) => !allowed.has(toolset));
  if (denied.length > 0) {
    throw new Error(`Hermes toolsets are outside OFXGGML_HERMES_SAFE_TOOLSETS: ${denied.join(", ")}`);
  }
  return {
    value: toolsets.join(","),
    requested: toolsets,
    allowed: Array.from(allowed),
  };
}

function endpointModelsUrl(endpoint) {
  const root = endpoint.endsWith("/") ? endpoint.slice(0, -1) : endpoint;
  return `${root}/models`;
}

function endpointKey(value) {
  const parsed = new URL(value);
  const normalizedPath = parsed.pathname.replace(/\/+$/, "");
  return `${parsed.protocol}//${parsed.host}${normalizedPath}`;
}

function endpointAllowlist() {
  const configured = splitCommaList(process.env.OFXGGML_HERMES_ENDPOINT_ALLOWLIST);
  const entries = configured.length > 0 ? configured : splitCommaList(defaultHermesEndpointAllowlist);
  return entries.map(endpointKey);
}

function resolveEndpoint(value) {
  const endpoint = resolveString(value, process.env.OFXGGML_HERMES_BASE_URL || defaultHermesBaseUrl);
  let key;
  try {
    key = endpointKey(endpoint);
  } catch (error) {
    throw new Error(`Hermes endpoint is not a valid URL: ${endpoint}`);
  }
  const allowed = new Set(endpointAllowlist());
  if (!allowed.has(key)) {
    throw new Error(`Hermes endpoint is outside OFXGGML_HERMES_ENDPOINT_ALLOWLIST: ${endpoint}`);
  }
  return endpoint;
}

async function checkEndpointModels(endpoint, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(endpointModelsUrl(endpoint), {
      signal: controller.signal,
      headers: { authorization: "Bearer local-dummy-key" },
    });
    const text = await response.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch (_) {}
    const modelIds = json && Array.isArray(json.data)
      ? json.data.map((entry) => entry && entry.id).filter(Boolean)
      : [];
    return {
      ok: response.ok,
      status: response.status,
      modelIds,
    };
  } catch (error) {
    return {
      ok: false,
      error: error && error.message ? error.message : String(error),
    };
  } finally {
    clearTimeout(timer);
  }
}

function checkHermesVersion(command) {
  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let stdoutTruncated = false;
    let stderrTruncated = false;
    let settled = false;
    let proc;
    const timeoutMs = Math.min(command.timeoutMs, 10000);
    const finish = (result) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => {
      if (proc && !proc.killed) {
        proc.kill();
      }
      finish({
        ok: false,
        error: `Hermes version check timed out after ${timeoutMs}ms`,
        stdoutTruncated: false,
        stderrTruncated: false,
      });
    }, timeoutMs);
    try {
      proc = spawn(command.executable, ["--version"], {
        cwd: command.cwd,
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      });
    } catch (error) {
      finish({
        ok: false,
        error: error.message || String(error),
        stdoutTruncated: false,
        stderrTruncated: false,
      });
      return;
    }
    function appendBounded(current, chunk, streamName) {
      const next = current + chunk.toString("utf8");
      if (Buffer.byteLength(next, "utf8") <= command.outputLimitBytes) {
        return next;
      }
      if (streamName === "stdout") {
        stdoutTruncated = true;
      } else {
        stderrTruncated = true;
      }
      const marker = `\n[${streamName} truncated at ${command.outputLimitBytes} bytes]\n`;
      const safePrefix = Buffer.from(next, "utf8").slice(0, command.outputLimitBytes).toString("utf8");
      return safePrefix + marker;
    }
    proc.stdout.on("data", (chunk) => {
      if (!stdoutTruncated) {
        stdout = appendBounded(stdout, chunk, "stdout");
      }
    });
    proc.stderr.on("data", (chunk) => {
      if (!stderrTruncated) {
        stderr = appendBounded(stderr, chunk, "stderr");
      }
    });
    proc.on("error", (error) => {
      finish({
        ok: false,
        error: error.message || String(error),
        stdoutTruncated: false,
        stderrTruncated: false,
      });
    });
    proc.on("exit", (code) => {
      finish({
        ok: code === 0,
        code,
        version: stdout.trim(),
        stderr: stderr.trim(),
        stdoutTruncated,
        stderrTruncated,
      });
    });
  });
}

function resolveHermesCommand(args, options = {}) {
  const cwdInfo = resolveRunCwd(args.cwd);
  const model = resolveString(args.model, process.env.OFXGGML_HERMES_MODEL || defaultHermesModel);
  const provider = resolveString(args.provider, process.env.OFXGGML_HERMES_PROVIDER || defaultHermesProvider);
  const hermesExe = resolveString(process.env.OFXGGML_HERMES_EXE, defaultHermesExe);
  const toolsets = resolveToolsets(args.toolsets);
  const timeoutMs = resolveTimeoutMs(args.timeout_ms || process.env.OFXGGML_HERMES_TIMEOUT_MS, defaultTimeoutMs);
  const allowHooksPolicy = booleanValue(process.env.OFXGGML_HERMES_ALLOW_HOOKS, false);
  if (booleanValue(args.allow_hooks, false) && !allowHooksPolicy) {
    throw new Error("Hermes hooks require OFXGGML_HERMES_ALLOW_HOOKS=1");
  }
  const allowHooks = allowHooksPolicy && booleanValue(args.allow_hooks, false);
  const safeMode = booleanValue(args.safe_mode, booleanValue(process.env.OFXGGML_HERMES_SAFE_MODE, false));
  const outputLimitBytes = resolveOutputLimitBytes(process.env.OFXGGML_HERMES_OUTPUT_LIMIT_BYTES);
  const endpoint = resolveEndpoint(args.endpoint);
  const commandArgs = [
    "-z",
    options.prompt || "",
    "-m",
    model,
    "--provider",
    provider,
  ];
  if (safeMode) {
    commandArgs.push("--safe-mode");
  }
  if (allowHooks) {
    commandArgs.push("--accept-hooks");
  }
  if (toolsets.value) {
    commandArgs.push("-t", toolsets.value);
  }
  return {
    executable: hermesExe,
    args: commandArgs,
    cwd: cwdInfo.cwd,
    timeoutMs,
    allowedCwdRoots: cwdInfo.allowedRoots,
    allowHooks,
    safeMode,
    toolsets,
    outputLimitBytes,
    endpoint,
  };
}

function callHermesAgent(args) {
  const prompt = typeof args.prompt === "string" ? args.prompt.trim() : "";
  if (!prompt) {
    throw new Error("prompt is required");
  }

  const command = resolveHermesCommand(args, { prompt });

  if (args.dry_run) {
    return Promise.resolve(textContent(JSON.stringify({
      transport: "hermes one-shot cli",
      command,
    }, null, 2)));
  }

  return runHermes(command);
}

async function preflightHermesAgent(args) {
  const command = resolveHermesCommand(args, { prompt: "preflight" });
  const hermesVersion = await checkHermesVersion(command);
  const checkEndpoint = booleanValue(args.check_endpoint, false);
  const endpoint = checkEndpoint
    ? await checkEndpointModels(command.endpoint, Math.min(command.timeoutMs, 10000))
    : { ok: null, skipped: true, modelsUrl: endpointModelsUrl(command.endpoint) };
  return textContent(JSON.stringify({
    status: hermesVersion.ok && (endpoint.ok === null || endpoint.ok) ? "passed" : "needs_attention",
    hermes: hermesVersion,
    command: {
      executable: command.executable,
      cwd: command.cwd,
      model: command.args[3],
      provider: command.args[5],
      allowHooks: command.allowHooks,
      safeMode: command.safeMode,
      toolsets: command.toolsets.requested,
      allowedToolsets: command.toolsets.allowed,
      allowedCwdRoots: command.allowedCwdRoots,
      outputLimitBytes: command.outputLimitBytes,
    },
    endpoint,
  }, null, 2));
}

function runHermes(command) {
  return new Promise((resolve, reject) => {
    let proc;
    try {
      proc = spawn(command.executable, command.args, {
        cwd: command.cwd,
        stdio: ["ignore", "pipe", "pipe"],
        windowsHide: true,
      });
    } catch (error) {
      reject(new Error(`failed to start Hermes (${command.executable}): ${error.message || String(error)}`));
      return;
    }

    let stdout = "";
    let stderr = "";
    let stdoutTruncated = false;
    let stderrTruncated = false;
    let settled = false;

    function stopHermes() {
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
      if (error) {
        stopHermes();
        reject(error);
      } else {
        resolve(result);
      }
    }

    const timer = setTimeout(() => {
      settle(new Error(`Hermes timed out after ${command.timeoutMs}ms`));
    }, command.timeoutMs);

    function appendBounded(current, chunk, streamName) {
      const next = current + chunk.toString("utf8");
      if (Buffer.byteLength(next, "utf8") <= command.outputLimitBytes) {
        return next;
      }
      if (streamName === "stdout") {
        stdoutTruncated = true;
      } else {
        stderrTruncated = true;
      }
      const marker = `\n[${streamName} truncated at ${command.outputLimitBytes} bytes]\n`;
      const safePrefix = Buffer.from(next, "utf8").slice(0, command.outputLimitBytes).toString("utf8");
      return safePrefix + marker;
    }

    proc.stdout.on("data", (chunk) => {
      if (!stdoutTruncated) {
        stdout = appendBounded(stdout, chunk, "stdout");
      }
    });
    proc.stderr.on("data", (chunk) => {
      if (!stderrTruncated) {
        stderr = appendBounded(stderr, chunk, "stderr");
      }
    });
    proc.on("error", (error) => {
      settle(new Error(`failed to start Hermes (${command.executable}): ${error.message || String(error)}`));
    });
    proc.on("exit", (code) => {
      if (code === 0) {
        const suffix = stdoutTruncated ? "\n[Hermes stdout was truncated by ofxGgmlLlama.]" : "";
        settle(null, textContent((stdout.trim() + suffix).trim()));
        return;
      }
      const suffix = stderrTruncated ? "\n[Hermes stderr was truncated by ofxGgmlLlama.]" : "";
      const details = stderr.trim() ? `\nstderr: ${(stderr.trim() + suffix).trim()}` : "";
      settle(new Error(`Hermes exited with code ${code}.${details}`));
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
          "Use run_hermes_agent only when the user explicitly asks to run Hermes Agent as a sidecar agent.",
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
    if (name === "preflight_hermes_agent") {
      const result = await preflightHermesAgent(params.arguments || {});
      send({ jsonrpc: "2.0", id, result });
      return;
    }
    if (name !== "run_hermes_agent") {
      errorResponse(id, -32602, `unknown tool: ${name}`);
      return;
    }
    const result = await callHermesAgent(params.arguments || {});
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
