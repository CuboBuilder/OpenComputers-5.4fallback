package com.ocpatch.lua54fallback;

import net.neoforged.fml.ModList;
import net.neoforged.fml.common.Mod;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Server-side workaround for the Lua 5.4 crash in OpenComputers.
 *
 * <p>Redirects every CPU configured for the experimental Lua 5.4 architecture to
 * Lua 5.3, which uses the stable natives. See {@code DriverCPUMixin} and
 * PC-Logix/OpenComputers#142.</p>
 */
@Mod(Lua54Fallback.MOD_ID)
public final class Lua54Fallback {

    public static final String MOD_ID = "oc_lua54_fallback";

    private static final Logger LOG = LoggerFactory.getLogger("oc-lua54-fallback");

    public Lua54Fallback() {
        if (ModList.get().isLoaded("opencomputers")) {
            LOG.info("[oc-lua54-fallback] OpenComputers detected; "
                    + "CPUs set to Lua 5.4 will run Lua 5.3 instead.");
        } else {
            LOG.warn("[oc-lua54-fallback] OpenComputers is not installed; this mod does nothing.");
        }
    }
}
