# OpenComputers Lua 5.4 → 5.3 Fallback

> **Temporary workaround.** This exists only until the Lua 5.4 crash in
> OpenComputers is fixed upstream. When it is, delete this mod.

A **server-side** addon for [OpenComputers: Rebooted](https://github.com/PC-Logix/OpenComputers)
(NeoForge, Minecraft 1.21.1) that stops the Lua 5.4 architecture from killing
your server.

It does not repair anything. It makes every CPU configured for **Lua 5.4** run
**Lua 5.3** instead, which uses the stable natives.

- No config file.
- No world edits.
- Works on CPUs already placed in computers, racks and inventories.
- Server-side only.

---

## The problem

OpenComputers' experimental Lua 5.4 architecture runs on a JNI bridge
(`libjnlua54-*`). Its native code frees a `lua_State` while `lua_pcall` is still
using it. That is a **use-after-free below the Java boundary**, so:

- it cannot be caught — there is no Java exception;
- it cannot be guarded from Java, because the stale pointer still looks valid
  and `LuaState.isOpen()` still returns `true`;
- it takes down the **entire JVM** with an access violation:

```
#  SIGSEGV (0xb) ...
#  Problematic frame:
#  C  [OpenComputersMod-...-libjnlua54-linux-x86_64.so+0x1ad03]  lua_getfield+0x83
```

The crash typically fires during **chunk/rack saving**, via:

```
Rack.saveAdditional → ComponentInventory.save → Server.saveData
  → Server.loadPendingMachineData → Machine.loadData
  → NativeLuaArchitecture.loadData → PersistenceAPI.unpersist
  → LuaState.call → lua_pcall → lua_getfield → SIGSEGV
```

Reported upstream as
[PC-Logix/OpenComputers#142](https://github.com/PC-Logix/OpenComputers/issues/142).

### Why not just fix it?

The fix belongs in the prebuilt OC-JNLua native libraries, which would have to be
rebuilt and republished for every platform (Linux, Windows, macOS, ARM, x86...).
That cannot be done from an addon. So this mod avoids the broken architecture
entirely.

---

## How it works

OpenComputers resolves a CPU's stored architecture through one call:

```java
// DriverCPU.architecture(ItemStack)
Class.forName(storedArchClassName)
```

A single Mixin redirects that call. If the requested class is
`NativeLua54Architecture`, it returns `NativeLua53Architecture` instead.

Because this happens at *read* time, it covers:

- CPUs already installed in computers,
- CPUs in racks and component inventories,
- CPUs in chests and player inventories,
- CPUs crafted after the mod was installed.

Nothing is written to the world. Removing the mod restores the previous
behaviour immediately.

### Verified

| Check | Result |
| --- | --- |
| `./gradlew build` | BUILD SUCCESSFUL |
| Mixin applies to `li.cil.oc.integration.opencomputers.DriverCPU` | yes, no injection failure |
| Dev server with OpenComputers | `Done (3.720s)!` |
| Lua 5.4 request returns Lua 5.3 | yes |
| Result is a valid `Architecture` | yes |
| Lua 5.3 passes through unchanged | yes |

---

## Requirements

| | |
| --- | --- |
| Minecraft | 1.21.1 |
| NeoForge | 21.1+ (built against 21.1.248, tested on 21.1.265) |
| Java | 21 |
| OpenComputers: Rebooted | any version (release or dev) |

Lua 5.3 must be available in your OpenComputers build. It is enabled by default
(`enableLua53`). If it is not, this mod logs a warning and leaves the CPU
untouched rather than making it unusable.

---

## Installation

1. Drop `oc-lua54-fallback-1.0.0.jar` into your server's `mods/` folder, next to
   OpenComputers.
2. Start the server. That is all.

You should see in the log:

```
Mixing DriverCPUMixin from oc_lua54_fallback.mixins.json into li.cil.oc.integration.opencomputers.DriverCPU
[oc-lua54-fallback] OpenComputers detected; CPUs set to Lua 5.4 will run Lua 5.3 instead.
```

### Checking a CPU

Look at the CPU item's tooltip in-game. A CPU that was saved as *Lua 5.4* will
now report **Lua 5.3**. The change is applied when the item is read, so the
stored value is left alone and reverts if you remove the mod.

---

## Side effects

- **Lua 5.4 features are gone on those CPUs.** Scripts written for 5.4-specific
  behaviour will run under 5.3 semantics instead. In practice 5.3 and 5.4 are
  close; the main difference is 5.4's `<const>`/`<close>` attributes and some
  integer/garbage-collector tuning.
- Machines that were mid-run in a 5.4 state may need a reboot after the switch.
- Nothing else is touched. Lua 5.2, LuaJ and Lua 5.3 CPUs behave exactly as
  before.

---

## Building from source

```bash
git clone <this-repo-url> oc-lua54-fallback
cd oc-lua54-fallback
./gradlew build
```

Output: `build/libs/oc-lua54-fallback-1.0.0.jar`.

### Dev environment

`runClient` / `runServer` need the OpenComputers jar on the dev classpath. Copy
it into `libs/` (gitignored) first:

```bash
mkdir -p libs
cp /path/to/mods/OpenComputers-*.jar "libs/OpenComputers-1.9.4-5.jar"
./gradlew runServer
```

---

## FAQ

### Should I use this or the crash-guard mod?

Use this one. The guard mod
([oc-lua54-patch](https://github.com/PC-Logix/OpenComputers/issues/142)) tried to
block the crash from Java and **did not work**: the pointer is freed after any
guard runs, so the check can never observe it. This mod avoids the defect
entirely, which is the only reliable option short of rebuilding the natives.

### Does this change my CPU items permanently?

No. The stored architecture tag is never written. The substitution happens when
the CPU is read.

### Can I still use Lua 5.4 elsewhere?

Not through these CPUs. If you need real Lua 5.4 you have to wait for an upstream
native fix.

### Why is the version range `*`?

NeoForge ranks `1.9.4-dev.417` as *older* than `1.9.4-5`, so a lower bound would
reject dev builds for no reason. The mixin is non-optional, so an incompatible
future version fails loudly instead of silently doing nothing.

---

## Credits & licence

- Patch code: MIT (see `LICENSE`).
- [OpenComputers](https://github.com/PC-Logix/OpenComputers) — MIT / CC0.
- [OC-JNLua](https://github.com/MightyPirates/OC-JNLua) — where the defect lives.

Unaffiliated with the OpenComputers maintainers.
