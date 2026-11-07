# OpenComputers Lua 5.4 → 5.3 Fallback

> ### ⚠ Unmaintained · AI-generated · use at your own risk
>
> This is a throwaway workaround written by an AI (a large language model) and
> it **will not be maintained**. No support, no updates, no guarantees.
>
> **Its only goal is to stop you from losing access to your world** because of a
> hard server crash. The proper fix belongs upstream in OpenComputers; once that
> lands, delete this mod.
>
> Read the [Disclaimer](#disclaimer) before installing.

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

### Expected one-time error in the log

On the first load after installing, you will likely see **one** message per
affected computer:

```
[OpenComputers/]: Unexpected error loading a state of computer at (...).
java.lang.Exception: ... LuaRuntimeException: trying to unpersist unknown type 10
```

**This is normal and harmless.** The saved Lua snapshot was written by Lua 5.4
and contains a value type that 5.3 does not know. OpenComputers catches the
error, discards the in-memory state and reboots the machine through the BIOS,
keeping its components, disks and filesystem intact. After it saves again the
snapshot is stored as 5.3 and the message will not return.

The trade-off: that machine's **volatile** state (running program, variables) is
lost once. Anything persistent survives.

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

## Disclaimer

**This mod is AI-generated and unmaintained.**

- It was written by a large language model. It has not been reviewed by a human
  expert and comes with **no warranty of any kind**.
- **It will not be maintained.** No bug fixes, no version updates, no support.
  If OpenComputers changes, this mod may break or silently do nothing.
- It is a **crash workaround, not a fix**. Its single purpose is to keep your
  world accessible instead of having the server killed by a JVM access
  violation. It does not repair the underlying defect in the OpenComputers
  native libraries.
- It works by **downgrading CPUs from Lua 5.4 to Lua 5.3**. If your scripts
  depend on 5.4-only behaviour, they will behave differently. Read
  [Side effects](#side-effects).
- Tested only against the setup described above. **Back up your world before
  installing.** No liability is accepted for lost data, broken worlds or
  anything else.
- Unaffiliated with, and not endorsed by, the OpenComputers maintainers.

If a crash that this mod does not cover still occurs, the correct place to
report it is
[PC-Logix/OpenComputers](https://github.com/PC-Logix/OpenComputers/issues),
not this project.

---

## Credits & licence

- This mod's own code: **MIT** (see `LICENSE`). Chosen to match the permissive
  terms of OpenComputers itself, so the two are compatible in every direction.
- [OpenComputers: Rebooted](https://github.com/PC-Logix/OpenComputers) —
  MIT for code, CC0 for assets. This mod **contains no OpenComputers code or
  assets**: it only references upstream class *names* at runtime through a
  Mixin, which is permitted under MIT and does not create a derivative work.
- [OC-JNLua](https://github.com/MightyPirates/OC-JNLua) — where the defect that
  motivates this workaround lives.

No OpenComputers files are redistributed here, so their copyright notices are
not reproduced in this repository.
