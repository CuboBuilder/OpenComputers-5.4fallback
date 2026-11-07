package com.ocpatch.lua54fallback.mixin;

import li.cil.oc.api.machine.Architecture;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Redirect;

/**
 * Substitutes the Lua 5.4 architecture with Lua 5.3 for every CPU.
 *
 * <p>OpenComputers' Lua 5.4 support is backed by a JNI bridge whose native code
 * frees a {@code lua_State} while {@code lua_pcall} is still using it. That is a
 * use-after-free below the Java boundary: it cannot be caught, it is invisible
 * to {@code isOpen()} and similar guards because the stale pointer still looks
 * valid, and it takes down the entire JVM with
 * {@code EXCEPTION_ACCESS_VIOLATION} / {@code SIGSEGV} in
 * {@code lua_getfield}. See PC-Logix/OpenComputers#142.</p>
 *
 * <p>Since the native bug cannot be repaired from Java, this mod sidesteps it:
 * any CPU configured to run Lua 5.4 is silently reported as Lua 5.3, which uses
 * the stable Lua 5.3 natives. This applies while a CPU is being read by the
 * machine, so it covers CPUs already placed in computers, racks and inventories
 * and requires no world edits.</p>
 *
 * <p>The redirect targets the single {@code Class.forName(archClass)} call in
 * {@code DriverCPU.architecture(ItemStack)}, which is the one place OpenComputers
 * turns the stored class name into an architecture class.</p>
 */
@Mixin(targets = "li.cil.oc.integration.opencomputers.DriverCPU", remap = false)
public abstract class DriverCPUMixin {

    /** The architecture that is unsafe to run and must be replaced. */
    private static final String OCPATCH$LUA54 = "li.cil.oc.server.machine.luac.NativeLua54Architecture";

    /** The replacement architecture. */
    private static final String OCPATCH$LUA53 = "li.cil.oc.server.machine.luac.NativeLua53Architecture";

    /**
     * Replaces {@code Class.forName(archClass)} so a stored Lua 5.4 CPU resolves
     * to Lua 5.3 instead.
     *
     * <p>If Lua 5.3 is not available in this OpenComputers build, the original
     * class is returned unchanged rather than breaking the CPU.</p>
     */
    @Redirect(
            method = "architecture",
            at = @At(value = "INVOKE",
                    target = "Ljava/lang/Class;forName(Ljava/lang/String;)Ljava/lang/Class;"),
            remap = false)
    private Class<?> ocpatch$substituteLua54(String className) throws ClassNotFoundException {
        if (OCPATCH$LUA54.equals(className)) {
            try {
                Class<?> fallback = Class.forName(OCPATCH$LUA53);
                if (Architecture.class.isAssignableFrom(fallback)) {
                    li.cil.oc.OpenComputers.log().debug(
                            "[oc-lua54-fallback] CPU configured for Lua 5.4 will run Lua 5.3 instead.");
                    return fallback;
                }
            } catch (ClassNotFoundException e) {
                // Lua 5.3 is not registered in this build; leave the CPU as-is
                // rather than making it unusable.
                li.cil.oc.OpenComputers.log().warn(
                        "[oc-lua54-fallback] Lua 5.3 architecture not found; leaving CPU on Lua 5.4.");
            }
            return Class.forName(className);
        }
        return Class.forName(className);
    }
}
