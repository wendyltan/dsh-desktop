#!/usr/bin/env node
// patchctl.mjs — 维护 profile 的 cordis.patch.yml（本地插件挂载/卸载/启停）
// 用法: patchctl.mjs <patch-file> <list|add|remove|enable|disable> <id> [name]
import { readFileSync, writeFileSync } from "node:fs";
import YAML from "yaml";

const [file, cmd, id, name] = process.argv.slice(2);
if (!file || !cmd) {
  console.error("usage: patchctl.mjs <patch-file> <list|add|remove|enable|disable> <id> [name]");
  process.exit(2);
}

let doc;
try {
  doc = YAML.parseDocument(readFileSync(file, "utf8"));
} catch {
  doc = YAML.parseDocument("[]");
}
const root = doc.contents ?? new YAML.YAMLSeq();

// 遍历所有 insert 列表里的条目
function entries() {
  const out = [];
  for (const node of root.items ?? []) {
    const ins = node?.get?.("insert");
    if (Array.isArray(ins?.items)) {
      for (const e of ins.items) {
        if (e?.get) out.push({ node: e, id: String(e.get("id") ?? "") });
      }
    }
  }
  return out;
}

switch (cmd) {
  case "list": {
    const list = entries().map((e) => ({
      id: e.id,
      name: String(e.node.get("name") ?? ""),
      disabled: e.node.get("disabled") === true,
    }));
    console.log(JSON.stringify(list));
    break;
  }
  case "add": {
    if (!id || !name) { console.error("add 需要 id 和 name"); process.exit(2); }
    if (entries().some((e) => e.id === id)) { console.error(`已存在 ${id}`); process.exit(1); }
    const entry = new YAML.YAMLMap();
    entry.set("id", id);
    entry.set("name", name);
    const seq = new YAML.YAMLSeq();
    seq.add(entry);
    const patch = new YAML.YAMLMap();
    patch.set("insert", seq);
    root.add(patch);
    writeFileSync(file, String(doc));
    console.log(`added ${id} -> ${name}`);
    break;
  }
  case "remove": {
    const found = entries().find((e) => e.id === id);
    if (!found) { console.error(`未找到 ${id}`); process.exit(1); }
    for (const node of root.items ?? []) {
      const ins = node?.get?.("insert");
      if (Array.isArray(ins?.items)) {
        const idx = ins.items.findIndex((e) => e?.get?.("id") === id);
        if (idx >= 0) {
          ins.items.splice(idx, 1);
          if (ins.items.length === 0) root.items.splice(root.items.indexOf(node), 1);
        }
      }
    }
    writeFileSync(file, String(doc));
    console.log(`removed ${id}`);
    break;
  }
  case "enable":
  case "disable": {
    const found = entries().find((e) => e.id === id);
    if (!found) { console.error(`未找到 ${id}`); process.exit(1); }
    if (cmd === "disable") found.node.set("disabled", true);
    else found.node.delete("disabled");
    writeFileSync(file, String(doc));
    console.log(`${cmd} ${id}`);
    break;
  }
  default:
    console.error(`未知命令 ${cmd}`);
    process.exit(2);
}
