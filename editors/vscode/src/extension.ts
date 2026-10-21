// The vole extension: starts `volec lsp` as a language server over stdio.
//
// The server gives diagnostics, go to definition, references, hover and
// document symbols. The compiler is found from the settings:
// vole.server.path (default `volec`, looked up on PATH), then
// vole.server.fallbackPath (default `tachyonc`, the compiler's name until
// the rename in 0.24). Nothing here talks to the network or collects
// telemetry.

import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from "vscode-languageclient/node";

let client: LanguageClient | undefined;
let output: vscode.OutputChannel | undefined;

export async function activate(context: vscode.ExtensionContext): Promise<void> {
  output = vscode.window.createOutputChannel("Vole");
  context.subscriptions.push(output);

  context.subscriptions.push(
    vscode.commands.registerCommand("vole.restartServer", async () => {
      await stopClient();
      await startClient(context);
    }),
    vscode.commands.registerCommand("vole.showOutput", () => output?.show(true)),
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (e.affectsConfiguration("vole.server")) {
        await stopClient();
        await startClient(context);
      }
    }),
  );

  await startClient(context);
}

export async function deactivate(): Promise<void> {
  await stopClient();
}

async function startClient(_context: vscode.ExtensionContext): Promise<void> {
  const config = vscode.workspace.getConfiguration("vole");
  if (!config.get<boolean>("server.enabled", true)) {
    log("the language server is disabled (vole.server.enabled)");
    return;
  }

  const compiler = findCompiler(config);
  if (!compiler) {
    const primary = config.get<string>("server.path", "volec");
    const fallback = config.get<string>("server.fallbackPath", "tachyonc");
    const msg =
      `Vole: no compiler found (tried "${primary}" and "${fallback}"). ` +
      `Set vole.server.path to the volec binary; syntax highlighting works without it.`;
    log(msg);
    const choice = await vscode.window.showWarningMessage(msg, "Open Settings");
    if (choice === "Open Settings") {
      await vscode.commands.executeCommand("workbench.action.openSettings", "vole.server");
    }
    return;
  }

  const args = config.get<string[]>("server.args", ["lsp"]);
  const cwd = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  log(`starting ${compiler} ${args.join(" ")}${cwd ? ` in ${cwd}` : ""}`);

  const run = { command: compiler, args, transport: TransportKind.stdio, options: { cwd } };
  const serverOptions: ServerOptions = { run, debug: run };
  const clientOptions: LanguageClientOptions = {
    documentSelector: [
      { scheme: "file", language: "vole" },
      { scheme: "untitled", language: "vole" },
    ],
    outputChannel: output,
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher("**/*.{vl,tach}"),
    },
  };

  client = new LanguageClient("vole", "Vole Language Server", serverOptions, clientOptions);
  try {
    await client.start();
  } catch (err) {
    const msg = `Vole: the language server did not start (${compiler} ${args.join(" ")}): ${String(err)}`;
    log(msg);
    void vscode.window.showErrorMessage(msg, "Show Output").then((c) => {
      if (c === "Show Output") output?.show(true);
    });
    client = undefined;
    return;
  }
}

async function stopClient(): Promise<void> {
  const c = client;
  client = undefined;
  if (c) {
    try {
      await c.stop();
    } catch (err) {
      log(`stopping the server: ${String(err)}`);
    }
  }
}

// The first of server.path and server.fallbackPath that names a runnable
// file: a path with a separator is taken as it is (relative to the first
// workspace folder), a bare name is looked up on PATH.
function findCompiler(config: vscode.WorkspaceConfiguration): string | undefined {
  const candidates = [
    config.get<string>("server.path", "volec"),
    config.get<string>("server.fallbackPath", "tachyonc"),
  ].filter((c): c is string => typeof c === "string" && c.trim() !== "");
  for (const c of candidates) {
    const found = resolveExecutable(expandHome(c.trim()));
    if (found) return found;
  }
  return undefined;
}

function resolveExecutable(name: string): string | undefined {
  if (name.includes("/") || name.includes("\\")) {
    const root = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
    const full = path.isAbsolute(name) || !root ? name : path.join(root, name);
    return isExecutable(full) ? full : undefined;
  }
  const exts = process.platform === "win32" ? (process.env.PATHEXT ?? ".EXE").split(";") : [""];
  for (const dir of (process.env.PATH ?? "").split(path.delimiter)) {
    if (!dir) continue;
    for (const ext of exts) {
      const full = path.join(dir, name + ext);
      if (isExecutable(full)) return full;
    }
  }
  return undefined;
}

function isExecutable(file: string): boolean {
  try {
    const st = fs.statSync(file);
    if (!st.isFile()) return false;
    if (process.platform === "win32") return true;
    fs.accessSync(file, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function expandHome(p: string): string {
  if (p === "~" || p.startsWith("~/")) {
    return path.join(process.env.HOME ?? "", p.slice(1));
  }
  return p;
}

function log(msg: string): void {
  output?.appendLine(`[${new Date().toISOString()}] ${msg}`);
}
