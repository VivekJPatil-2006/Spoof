#!/usr/bin/env node
"use strict";

const os = require("os");
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
function flag(name) { return args.includes(name); }
function value(name, fallback = "") {
  const i = args.indexOf(name);
  return i === -1 ? fallback : args[i + 1] || fallback;
}
if (flag("--help") || flag("-h")) {
  console.log("Uso: node ghost-check.js [opciones]");
  console.log("");
  console.log("Opciones:");
  console.log("  --banned-programs <file>  Catálogo JSON de procesos prohibidos");
  console.log("  --advanced                Verificación avanzada (drivers, servicios, registro)");
  console.log("  --json                    Salida JSON");
  console.log("");
  console.log("Replica exactamente lo que hacen SMOWL y OnVUE:");
  console.log("  si.system()    -> comprueba .virtual y .manufacturer");
  console.log("  si.diskLayout() -> comprueba nombre y vendor del disco");
  console.log("  si.processes() -> enumera procesos y compara con banned-programs");
  console.log("  si.osInfo()    -> informacion del SO");
  process.exit(0);
}

const RED = "\x1b[31m";
const NC = "\x1b[0m";

const VM_TEXT_PATTERNS = [
  /virtualbox/i, /innotek/i, /oracle/i, /vbox/i, /vmware/i,
  /qemu/i, /kvm/i, /xen/i, /hyper-v/i, /parallels/i, /bochs/i,
];

const VM_DISK_PATTERNS = [
  /vbox/i, /virtual/i, /vmdk/i, /qemu/i, /vmware/i,
];

function hasVmText(text) {
  return VM_TEXT_PATTERNS.some(p => p.test(text));
}

function loadBannedPrograms(filePath) {
  if (!filePath) {
    // Cargar el fichero por defecto segun el OS
    const platform = process.platform === "win32" ? "windows" : process.platform === "darwin" ? "macos" : "linux";
    filePath = path.join(__dirname, `banned-${platform}.json`);
  }
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    const data = JSON.parse(raw);
    const programs = [];
    for (const category of (data.categories || data)) {
      const progs = category.programs || [];
      for (const p of progs) {
        const names = p.processes || p.windows || p.macos || p.linux || [];
        for (const name of names) programs.push(name.toLowerCase());
      }
    }
    return [...new Set(programs)];
  } catch {
    return [];
  }
}

async function main() {
  const si = require("systeminformation");
  const findings = [];
  const notes = [];
  let score = 0;

  function addFinding(severity, category, detail) {
    findings.push({ severity, category, detail });
    if (severity === "high") score += 30;
    else if (severity === "medium") score += 10;
    else score += 5;
  }

  console.log("[GHOST CHECK] Verificacion de camuflaje de VM");
  console.log(`  Plataforma: ${os.platform()} ${os.arch()}`);
  console.log(`  Node: ${process.version}`);
  console.log("");

  // 1. si.system() - lo que SMOWL comprueba
  try {
    const system = await si.system();
    console.log("[1] systeminformation.system()");
    console.log(`    manufacturer: ${system.manufacturer}`);
    console.log(`    model: ${system.model}`);
    console.log(`    virtual: ${system.virtual}`);
    console.log(`    virtualHost: ${system.virtualHost || "(n/a)"}`);
    console.log(`    serial: ${system.serial}`);
    console.log(`    uuid: ${system.uuid}`);
    console.log("");

    if (system.virtual) {
      addFinding("high", "system.virtual", "true - VM detectada por systeminformation");
    }
    if (hasVmText(system.manufacturer)) {
      addFinding("high", "system.manufacturer", `${system.manufacturer} - contiene texto de VM`);
    }
    if (hasVmText(system.model)) {
      addFinding("high", "system.model", `${system.model} - contiene texto de VM`);
    }
    if (system.virtualHost && hasVmText(system.virtualHost)) {
      addFinding("high", "system.virtualHost", `${system.virtualHost} - contiene texto de VM`);
    }
    if (hasVmText(system.serial || "")) {
      addFinding("medium", "system.serial", `${system.serial} - contiene texto de VM`);
    }
  } catch (e) {
    notes.push(`No se pudo leer system(): ${e.message}`);
  }

  // 2. si.diskLayout() - lo que SMOWL comprueba
  try {
    const disks = await si.diskLayout();
    console.log("[2] systeminformation.diskLayout()");
    for (const disk of disks) {
      console.log(`    ${disk.name} (${disk.vendor}) - ${disk.size} bytes`);
      if (hasVmText(disk.name) || VM_DISK_PATTERNS.some(p => p.test(disk.name))) {
        addFinding("high", "disk.name", `${disk.name} - disco virtual detectado`);
      }
      if (hasVmText(disk.vendor || "")) {
        addFinding("medium", "disk.vendor", `${disk.vendor} - vendor de VM`);
      }
    }
    console.log("");
  } catch (e) {
    notes.push(`No se pudo leer diskLayout(): ${e.message}`);
  }

  // 3. si.processes() - lo que SMOWL y OnVUE comprueban
  try {
    const procs = await si.processes();
    const banned = loadBannedPrograms(value("--banned-programs"));
    console.log("[3] systeminformation.processes()");
    console.log(`    Procesos totales: ${procs.all}`);
    console.log(`    Catalogo banned: ${banned.length} entradas`);
    console.log("");

    const found = new Set();
    for (const p of (procs.list || [])) {
      const name = (p.name || "").toLowerCase();
      const proc = (p.proc || "").toLowerCase();
      const cmd = (p.command || "").toLowerCase();
      for (const b of banned) {
        if (name === b || proc === b || cmd.includes(b)) {
          found.add(b);
        }
      }
    }
    if (found.size > 0) {
      for (const f of found) {
        addFinding("high", "process.banned", `${f} - proceso prohibido en ejecucion`);
      }
      console.log(`    ${RED}PROCESOS PROHIBIDOS: ${[...found].join(", ")}${NC}`);
    } else {
      console.log(`    No hay procesos prohibidos en ejecucion`);
    }
    console.log("");
  } catch (e) {
    notes.push(`No se pudo leer processes(): ${e.message}`);
  }

  // 4. si.osInfo() - lo que SMOWL comprueba
  try {
    const osInfo = await si.osInfo();
    console.log("[4] systeminformation.osInfo()");
    console.log(`    platform: ${osInfo.platform}`);
    console.log(`    distro: ${osInfo.distro}`);
    console.log(`    release: ${osInfo.release}`);
    console.log(`    arch: ${osInfo.arch}`);
    console.log("");
    if (hasVmText(osInfo.distro || "")) {
      addFinding("medium", "osInfo.distro", `${osInfo.distro} - contiene texto de VM`);
    }
  } catch (e) {
    notes.push(`No se pudo leer osInfo(): ${e.message}`);
  }

  // 5. si.uuid() - lo que OnVUE comprueba
  try {
    const uuid = await si.uuid();
    console.log("[5] systeminformation.uuid()");
    console.log(`    hardware: ${uuid.hardware}`);
    console.log(`    os: ${uuid.os}`);
    console.log("");
    if (hasVmText(uuid.hardware || "")) {
      addFinding("high", "uuid.hardware", `${uuid.hardware} - UUID contiene texto de VM`);
    }
  } catch (e) {
    notes.push(`No se pudo leer uuid(): ${e.message}`);
  }

  // 6. Verificacion avanzada
  if (flag("--advanced")) {
    console.log("[6] Verificacion avanzada");

    if (process.platform === "win32") {
      try {
        const { execSync } = require("child_process");
        const hypervisor = execSync(
          'powershell -NoProfile -Command "Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty HypervisorPresent"',
          { encoding: "utf8", timeout: 5000 }
        ).trim();
        console.log(`    HypervisorPresent: ${hypervisor}`);
        if (/true/i.test(hypervisor)) {
          addFinding("high", "windows.HypervisorPresent", "true - Windows detecta hypervisor");
        }
      } catch {
        notes.push("No se pudo leer HypervisorPresent");
      }

      try {
        const { execSync } = require("child_process");
        const drivers = execSync(
          'powershell -NoProfile -Command "Get-CimInstance Win32_SystemDriver | Where-Object {$_.State -eq \'Running\'} | Select-Object -ExpandProperty Name"',
          { encoding: "utf8", timeout: 10000 }
        );
        const vmDrivers = ["VBoxGuest", "VBoxMouse", "VBoxSF", "VBoxVideo", "VBoxWddm", "vmhgfs", "vmmouse"];
        for (const d of vmDrivers) {
          if (drivers.includes(d)) {
            addFinding("high", "windows.driver", `${d} - driver de VM activo`);
          }
        }
      } catch {
        notes.push("No se pudieron enumerar drivers");
      }
    }

    if (process.platform === "linux") {
      try {
        const cpuinfo = fs.readFileSync("/proc/cpuinfo", "utf8");
        const flagsLine = cpuinfo.split("\n").find(l => l.startsWith("flags"));
        if (flagsLine && /\bhypervisor\b/i.test(flagsLine)) {
          addFinding("high", "cpuinfo.flags", "flag hypervisor presente en /proc/cpuinfo");
        }
        console.log(`    /proc/cpuinfo hypervisor flag: ${flagsLine && /\bhypervisor\b/i.test(flagsLine) ? "SI" : "no"}`);
      } catch {
        notes.push("No se pudo leer /proc/cpuinfo");
      }
    }
    console.log("");
  }

  // 7. Perifericos: webcam, microfono, altavoces
  if (flag("--advanced")) {
    console.log("[7] Perifericos (webcam, microfono, altavoces)");
    try {
      const audio = await si.audio();
      console.log(`    Dispositivos de audio: ${audio.length}`);
      for (const a of audio) {
        console.log(`      ${a.name} (${a.manufacturer})`);
        if (hasVmText(a.name || "") || hasVmText(a.manufacturer || "")) {
          addFinding("medium", "audio.device", `${a.name} - contiene texto de VM`);
        }
      }
    } catch (e) {
      notes.push("No se pudo leer audio()");
    }

    try {
      const usb = await si.usb();
      console.log(`    Dispositivos USB: ${usb.length}`);
      for (const u of usb) {
        const name = (u.name || "") + " " + (u.vendor || "");
        console.log(`      ${u.name || "unknown"} (vendor: ${u.vendor || "n/a"})`);
        if (hasVmText(name)) {
          addFinding("low", "usb.device", `${u.name} - contiene texto de VM`);
        }
      }
    } catch (e) {
      notes.push("No se pudo leer usb()");
    }

    try {
      const camera = await si.camera();
      if (camera) {
        console.log(`    Camara: ${camera.name || "n/a"} (${camera.vendor || "n/a"})`);
        if (hasVmText(camera.name || "")) {
          addFinding("medium", "camera.name", `${camera.name} - contiene texto de VM`);
        }
      } else {
        console.log("    Camara: no detectada");
      }
    } catch (e) {
      notes.push("No se pudo leer camera()");
    }
    console.log("");
  }

  // Resultado
  console.log("============================================");
  console.log("  RESULTADO");
  console.log("============================================");
  console.log(`  Findings: ${findings.length}`);
  console.log(`  Score: ${Math.min(score, 100)}/100`);

  if (findings.length > 0) {
    console.log("");
    console.log("  Hallazgos:");
    for (const f of findings) {
      const color = f.severity === "high" ? "\x1b[31m" : f.severity === "medium" ? "\x1b[33m" : "\x1b[0m";
      console.log(`  ${color}[${f.severity.toUpperCase()}] ${f.category}: ${f.detail}\x1b[0m`);
    }
  }

  if (notes.length > 0) {
    console.log("");
    console.log("  Notas:");
    for (const n of notes) console.log(`  ${n}`);
  }

  console.log("");
  if (findings.length === 0) {
    console.log("  \x1b[32mPASS - No se detectaron indicadores de VM\x1b[0m");
    process.exit(0);
  } else {
    console.log("  \x1b[31mFAIL - Se detectaron indicadores de VM\x1b[0m");
    process.exit(1);
  }
}

main().catch(e => {
  console.error("Error:", e.message);
  process.exit(2);
});